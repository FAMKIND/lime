// POST send: a fan-out batch { ciphertext, recipients: [{ to_device, access }] }.
//
// `access` is { signed: "<Ed25519 signature, base64>" } (LIME-139: no user token needed; the server learns nothing about the sender), the
// older { sealed: "<access_key, base64>" } (kept during the overlap; remove it once every device has updated, before TestFlight) or { identified: true } (a user token is required; the item records the
// sender, so a stranger's first message can land in Requests). The server stores one item per
// recipient device, de-duplicated by SHA-256(ciphertext) per device, then nudges the device's
// Realtime channel (a private channel only its owner may join) with { type: "new" } (no content).
//
// LIME-120: `expect` (optional) is the sender's cached view of each recipient user's devices:
//   expect: { "<user_id>": { devices: ["<device_id>", ...], master: "<hex SHA-256 of the user's master key>" } }
// After the access checks (so only someone allowed to send to these devices learns anything) the server compares it with the live,
// non-revoked devices and the master key. On a difference it stores NOTHING and answers 409 `devices_changed` (a device appeared or
// the master key changed) or 410 `devices_revoked` (only revoked devices were named), with the current list for each user that
// differs: { stale: [{ user_id, master_key, devices: [{ device_id, identity_key, signing_key, master_signature }], missing, extra,
// master_changed }], revoked: [device ids] }. That is the same public data `users-devices` serves. The sender updates its cache and
// retries once. Without `expect` nothing changes (an old client). A normal response carries `checked: true` when `expect` was checked.
//
// Nothing here logs ciphertext, keys, access keys or tokens.

import { admin, config, rateLimit, requireUser } from "../_shared/db.ts";
import { constantTimeEqual, fromBase64, fromPgBytea, isUuid, sha256, toHex, toPgBytea, uuidBytes, verifyEd25519 } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

type Recipient = { to_device: string; access: { signed?: unknown; sealed?: unknown; identified?: unknown } };
type Access = { hash: Uint8Array | null; publicKey: Uint8Array | null };

/** What a signed send signs: a label, SHA-256 of the ciphertext and the recipient device's 16 raw UUID bytes (so a signature fits one message to one device only). */
const SIGNED_LABEL = new TextEncoder().encode("lime-access-v2");
type Expected = { devices: Set<string>; master: string };

/** The sender's `expect`, validated; null when the request has none (the old behaviour). */
function readExpect(value: unknown): Map<string, Expected> | null {
  if (value === undefined) return null;
  const bad = () => new HttpError(400, "bad_request", "expect must map user UUIDs to { devices, master }.");
  if (value === null || typeof value !== "object" || Array.isArray(value)) throw bad();
  const entries = Object.entries(value as Record<string, unknown>);
  if (entries.length === 0 || entries.length > 100) throw bad();
  const out = new Map<string, Expected>();
  for (const [userId, entry] of entries) {
    const e = entry as { devices?: unknown; master?: unknown } | null;
    if (!isUuid(userId) || !e || !Array.isArray(e.devices) || e.devices.length > 100 || !e.devices.every(isUuid) ||
        typeof e.master !== "string" || e.master.length > 128) throw bad();
    out.set(userId.toLowerCase(), { devices: new Set((e.devices as string[]).map((d) => d.toLowerCase())), master: e.master.toLowerCase() });
  }
  return out;
}

async function nudge(deviceIds: string[]): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key || deviceIds.length === 0) return;
  try {
    await fetch(`${url}/realtime/v1/api/broadcast`, {
      method: "POST",
      headers: { "content-type": "application/json", apikey: key, authorization: `Bearer ${key}` },
      body: JSON.stringify({
        messages: deviceIds.map((id) => ({ topic: `device:${id}`, event: "new", payload: { type: "new" }, private: true })),
      }),
    });
  } catch {
    // A missed nudge is harmless: the device also fetches when it opens.
  }
}

Deno.serve(handler(async (req) => {
  // The batch can hold hundreds of recipients plus a 64 KB ciphertext (base64).
  const body = await readJson(req, 512 * 1024);

  const recipients = body.recipients;
  if (!Array.isArray(recipients) || recipients.length === 0 || recipients.length > config.maxRecipientsPerSend()) {
    throw new HttpError(400, "bad_request", `Send to 1 to ${config.maxRecipientsPerSend()} recipients.`);
  }
  let ciphertext: Uint8Array;
  try {
    ciphertext = fromBase64(String(body.ciphertext));
  } catch {
    throw new HttpError(400, "bad_request", "ciphertext must be base64.");
  }
  if (ciphertext.length === 0) throw new HttpError(400, "bad_request", "ciphertext is empty.");
  if (ciphertext.length > config.maxItemBytes()) {
    throw new HttpError(413, "too_large", `An item may not exceed ${config.maxItemBytes()} bytes.`);
  }

  const expect = readExpect(body.expect);
  const list = recipients as Recipient[];
  for (const r of list) {
    if (!r || !isUuid(r.to_device) || typeof r.access !== "object" || r.access === null) {
      throw new HttpError(400, "bad_request", "Each recipient needs a to_device UUID and an access.");
    }
  }

  const ciphertextHash = await sha256(ciphertext);

  // A user token is needed only when some recipient is sent identified.
  const anyIdentified = list.some((r) => r.access.identified === true);
  const senderUser = anyIdentified ? await requireUser(req) : null;

  const db = admin();
  const deviceIds = [...new Set(list.map((r) => r.to_device.toLowerCase()))];
  const { data: devices, error: devicesError } = await db
    .from("devices").select("device_id, user_id, revoked_at").in("device_id", deviceIds);
  if (devicesError) throw new HttpError(500, "internal");
  const deviceById = new Map((devices ?? []).map((d) => [d.device_id as string, d]));

  // Check every recipient's access before storing anything: all or nothing. The access check comes first: only someone allowed to
  // send to a device may learn that it was revoked or that its user's devices changed (with `expect`).
  const checking = expect !== null;
  const revokedNamed: string[] = [];
  const accessByUser = new Map<string, Access>();
  const sealedCostByKey = new Map<string, number>(); // bucket -> items
  let identifiedItems = 0;
  for (const r of list) {
    const id = r.to_device.toLowerCase();
    const device = deviceById.get(id);
    const revoked = !!device && device.revoked_at !== null;
    if (r.access.identified === true) {
      if (!device) throw new HttpError(404, "unknown_device", "A recipient device is unknown or revoked.");
      if (revoked) {
        if (!checking) throw new HttpError(404, "unknown_device", "A recipient device is unknown or revoked.");
        revokedNamed.push(id);
        continue;
      }
      identifiedItems++;
      continue;
    }
    // Sealed (signed, or the older access key). A wrong key or signature, a missing key and an unknown device all look the same: 403.
    // (A revoked device is the same without `expect`; with it, the proof is checked first and a revoked device is then reported, to the
    // holder of the key only.)
    const denied = () => new HttpError(403, "access_denied", "The access key was not accepted.");
    const signed = typeof r.access.signed === "string";
    if (!device || (revoked && !checking) || (!signed && typeof r.access.sealed !== "string")) throw denied();
    if (!accessByUser.has(device.user_id)) {
      const { data } = await db.from("delivery_access").select("access_key_hash, access_public_key").eq("user_id", device.user_id).maybeSingle();
      accessByUser.set(device.user_id, {
        hash: data?.access_key_hash ? fromPgBytea(data.access_key_hash as string) : null,
        publicKey: data?.access_public_key ? fromPgBytea(data.access_public_key as string) : null,
      });
    }
    const stored = accessByUser.get(device.user_id)!;
    let bucketKey: Uint8Array;
    if (signed) {
      // The signature covers this ciphertext and this device: it cannot be replayed for another message or another device.
      let signature: Uint8Array;
      try {
        signature = fromBase64(r.access.signed as string);
      } catch {
        throw denied();
      }
      if (!stored.publicKey || signature.length !== 64) throw denied();
      const message = new Uint8Array(SIGNED_LABEL.length + 32 + 16);
      message.set(SIGNED_LABEL, 0);
      message.set(ciphertextHash, SIGNED_LABEL.length);
      message.set(uuidBytes(id), SIGNED_LABEL.length + 32);
      if (!(await verifyEd25519(stored.publicKey, signature, message))) throw denied();
      bucketKey = await sha256(stored.publicKey);
    } else {
      let presented: Uint8Array;
      try {
        presented = fromBase64(r.access.sealed as string);
      } catch {
        throw denied();
      }
      if (presented.length !== 16) throw denied();
      const presentedHash = await sha256(presented);
      if (!stored.hash || !constantTimeEqual(stored.hash, presentedHash)) throw denied();
      bucketKey = presentedHash;
    }
    if (revoked) {
      revokedNamed.push(id);
      continue;
    }
    const bucket = `send:access:${toHex(bucketKey)}`;
    sealedCostByKey.set(bucket, (sealedCostByKey.get(bucket) ?? 0) + 1);
  }

  // `expect`: the sender's view of each user's devices against the live ones. A difference stores nothing.
  if (expect) {
    const userIds = [...expect.keys()];
    const { data: liveDevices, error: liveError } = await db
      .from("devices").select("device_id, user_id, identity_key, signing_key, master_signature")
      .in("user_id", userIds).is("revoked_at", null).order("created_at");
    const { data: masters, error: mastersError } = await db.from("master_keys").select("user_id, public_key").in("user_id", userIds);
    if (liveError || mastersError) throw new HttpError(500, "internal");
    const stale = [];
    let onlyRevoked = true;
    for (const [userId, expected] of expect) {
      const live = (liveDevices ?? []).filter((d) => d.user_id === userId);
      const liveIds = new Set(live.map((d) => d.device_id as string));
      const masterKey = ((masters ?? []).find((m) => m.user_id === userId)?.public_key as string | undefined) ?? null;
      const masterHash = masterKey ? toHex(await sha256(new TextEncoder().encode(masterKey))) : "";
      const missing = [...liveIds].filter((d) => !expected.devices.has(d));
      const extra = [...expected.devices].filter((d) => !liveIds.has(d));
      const masterChanged = masterHash !== expected.master;
      if (missing.length === 0 && extra.length === 0 && !masterChanged) continue;
      if (missing.length > 0 || masterChanged) onlyRevoked = false;
      stale.push({
        user_id: userId,
        master_key: masterKey,
        devices: live.map((d) => ({ device_id: d.device_id, identity_key: d.identity_key, signing_key: d.signing_key, master_signature: d.master_signature })),
        missing, extra, master_changed: masterChanged,
      });
    }
    if (stale.length > 0 || revokedNamed.length > 0) {
      // Nothing is stored and nobody is nudged.
      return json({ error: onlyRevoked ? "devices_revoked" : "devices_changed", stale, revoked: revokedNamed }, onlyRevoked ? 410 : 409);
    }
  }

  // Rate limits: recipient-items per minute, per user (identified) or per access key (sealed).
  if (identifiedItems > 0 && senderUser) {
    await rateLimit(`send:user:${senderUser}`, identifiedItems, config.sendPerMinute(), 60);
  }
  for (const [bucket, cost] of sealedCostByKey) {
    await rateLimit(bucket, cost, config.sendPerMinute(), 60);
  }

  const seen = new Set<string>();
  const rows = [];
  for (const r of list) {
    const id = r.to_device.toLowerCase();
    if (seen.has(id)) continue;
    seen.add(id);
    const identified = r.access.identified === true;
    rows.push({
      to_device: id,
      ciphertext: toPgBytea(ciphertext),
      ciphertext_hash: toPgBytea(ciphertextHash),
      size: ciphertext.length,
      identified,
      sender_user: identified ? senderUser : null,
    });
  }

  // De-duplicate by SHA-256(ciphertext) per recipient device: a repeat is ignored.
  const { data: stored, error } = await db
    .from("mailbox_items")
    .upsert(rows, { onConflict: "to_device,ciphertext_hash", ignoreDuplicates: true })
    .select("to_device");
  if (error) throw new HttpError(500, "internal");
  const storedDevices = (stored ?? []).map((s) => s.to_device as string);

  await nudge(storedDevices);
  return json({ stored: storedDevices.length, duplicates: rows.length - storedDevices.length, checked: checking });
}));
