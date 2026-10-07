// POST devices-register: binds a device_id to the signed-in user and stores its public keys and
// the master-key signature (cross-signing). The signature is verified here.
//
// The signed message (decided in LIME-92, docs/api-v2.md section 11):
//   "lime-device-v1\n" + device_id + "\n" + identity_key + "\n" + signing_key
// as UTF-8, with the key strings exactly as sent, signed by the user's Ed25519 master key.
//
// The first registration fixes the account's master key. A LATER registration with a different master
// key (a phone whose keys were wiped) from a verified session replaces the account's keys: see the
// comment where it happens, and docs/api-v2.md section 11 (LIME-95-fix).

import { admin, config, rateLimit, requireUser } from "../_shared/db.ts";
import { fromBase64, isUuid, verifyEd25519 } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { keysReplacedNotice, sendNotice } from "../_shared/notify.ts";

function key32(value: unknown, name: string): string {
  try {
    if (typeof value !== "string" || fromBase64(value).length !== 32) throw new Error();
  } catch {
    throw new HttpError(400, "bad_request", `${name} must be a base64 32-byte key.`);
  }
  return value as string;
}

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const body = await readJson(req);
  if (!isUuid(body.device_id)) throw new HttpError(400, "bad_request", "device_id must be a UUID.");
  const deviceId = body.device_id.toLowerCase();
  const identityKey = key32(body.identity_key, "identity_key");
  const signingKey = key32(body.signing_key, "signing_key");
  const masterKey = key32(body.master_key, "master_key");
  let signature: Uint8Array;
  try {
    signature = fromBase64(String(body.master_signature));
    if (signature.length !== 64) throw new Error();
  } catch {
    throw new HttpError(400, "bad_request", "master_signature must be a base64 64-byte signature.");
  }

  await rateLimit(`register:${userId}`, 1, config.registerPerHour(), 3600);

  const message = new TextEncoder().encode(`lime-device-v1\n${deviceId}\n${identityKey}\n${signingKey}`);
  if (!(await verifyEd25519(fromBase64(masterKey), signature, message))) {
    throw new HttpError(400, "bad_signature", "The master-key signature does not verify.");
  }

  const db = admin();
  let keysReset = false;
  // The first registration fixes the account's master key. Two devices registering at once must not
  // race, so insert-if-absent, then read back and compare.
  {
    const { error } = await db.from("master_keys").upsert(
      { user_id: userId, public_key: masterKey },
      { onConflict: "user_id", ignoreDuplicates: true },
    );
    if (error) {
      console.error("master_keys insert failed", error.code); // the code only: no data, no keys
      throw new HttpError(500, "internal");
    }
    const { data: master } = await db.from("master_keys").select("public_key").eq("user_id", userId).maybeSingle();
    if (!master) throw new HttpError(500, "internal");
    if (master.public_key !== masterKey) {
      // A phone with new keys (a fresh install, or a sign-out that wiped the old ones). The session is
      // verified (a password AND an emailed code, `requireUser`), so it may replace the account's keys:
      // the old devices are revoked and their unreadable mail removed (migration 20261007000000).
      // Contacts that remembered the old master key must accept the change.
      const { error: resetError } = await db.rpc("reset_account_keys", { p_user: userId, p_master: masterKey });
      if (resetError) {
        console.error("reset_account_keys failed", resetError.code);
        throw new HttpError(500, "internal");
      }
      keysReset = true;
    }
  }

  const { data: existing } = await db.from("devices").select("*").eq("device_id", deviceId).maybeSingle();
  if (existing) {
    const same = existing.user_id === userId && existing.identity_key === identityKey &&
      existing.signing_key === signingKey && existing.master_signature === body.master_signature;
    if (!same) throw new HttpError(409, "device_exists", "That device id is already registered.");
  } else {
    const { error } = await db.from("devices").insert({
      device_id: deviceId,
      user_id: userId,
      identity_key: identityKey,
      signing_key: signingKey,
      master_signature: body.master_signature,
    });
    if (error) {
      console.error("devices insert failed", error.code);
      throw new HttpError(500, "internal");
    }
  }

  if (keysReset) {
    // Tell the account's owner (best effort: a failed send never blocks the registration).
    const { data: owner } = await db.auth.admin.getUserById(userId);
    if (owner?.user?.email) await sendNotice(owner.user.email, keysReplacedNotice());
  }

  const { data: remaining } = await db.rpc("remaining_one_time_keys", { p_device: deviceId });
  return json({ device_id: deviceId, user_id: userId, remaining_one_time_keys: remaining ?? 0, keys_reset: keysReset }, existing ? 200 : 201);
}));
