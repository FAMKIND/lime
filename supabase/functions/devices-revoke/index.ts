// POST devices-revoke (LIME-342a): unlinks a COMPUTER from my account.
//
//   { device_id, at, kind, master_signature }   (the caller's verified session)
//
// The signed message (UTF-8, signed by the account's Ed25519 master key; the strings exactly as sent):
//   "lime-revoke-v1\n" + user_id + "\n" + device_id + "\n" + at + "\n" + kind
// - `at` is milliseconds since the Unix epoch and must be within 5 minutes of now (a recorded request cannot be replayed later);
// - `kind` must be `computer`. A phone or a tablet holds the master secret (K2) and could sign anything, so removing one would change nothing until DESIGN-M2
//   (a master key that can be rotated): the client refuses, and a request that does not say `computer` is refused here too. The server cannot see what a
//   device is (it stores no kind and no name: only what it already stored), so this is the client's own signed statement, not something the server verifies.
// - a device cannot revoke itself (the caller names its own device in `from_device`; a request for that device is refused).
//
// The device is revoked in one atomic call (`revoke_device`): its unfetched mail and unused one-time keys are deleted and `revoked_at` is set; from then
// on every function refuses it (401 `revoked`), it is no longer listed or sent to. What the server learns: which device was revoked, when, by which
// account: nothing it did not already know (it knows the device ids and count).

import { admin, requireDevice, requireUser } from "../_shared/db.ts";
import { fromBase64, isUuid, verifyEd25519 } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

const FRESH_MS = 5 * 60 * 1000;

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const body = await readJson(req);
  if (!isUuid(body.device_id) || !isUuid(body.from_device)) throw new HttpError(400, "bad_request", "device_id and from_device must be UUIDs.");
  const target = body.device_id.toLowerCase();
  const from = body.from_device.toLowerCase();
  if (typeof body.at !== "number" || !Number.isInteger(body.at)) throw new HttpError(400, "bad_request", "at must be a whole number of milliseconds.");
  if (body.kind !== "computer") throw new HttpError(400, "bad_request", "Only a computer can be unlinked.");
  let signature: Uint8Array;
  try {
    signature = fromBase64(String(body.master_signature));
    if (signature.length !== 64) throw new Error();
  } catch {
    throw new HttpError(400, "bad_request", "master_signature must be a base64 64-byte signature.");
  }
  if (Math.abs(Date.now() - body.at) > FRESH_MS) throw new HttpError(400, "stale", "That request is too old.");
  if (target === from) throw new HttpError(400, "bad_request", "A device cannot unlink itself.");

  // The caller is one of the account's own, active devices.
  await requireDevice(userId, from);

  const db = admin();
  const { data: master } = await db.from("master_keys").select("public_key").eq("user_id", userId).maybeSingle();
  if (!master) throw new HttpError(404, "not_found", "No such account.");
  const message = new TextEncoder().encode(`lime-revoke-v1\n${userId}\n${target}\n${body.at}\n${body.kind}`);
  if (!(await verifyEd25519(fromBase64(master.public_key), signature, message))) {
    throw new HttpError(400, "bad_signature", "The master-key signature does not verify.");
  }

  const { data: revoked, error } = await db.rpc("revoke_device", { p_user: userId, p_device: target });
  if (error) {
    console.error("revoke_device failed", error.code);
    throw new HttpError(500, "internal");
  }
  if (revoked !== true) throw new HttpError(404, "not_found", "That device is not one of this account's active devices.");
  return json({ device_id: target, revoked: true });
}));
