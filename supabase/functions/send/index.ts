// POST send: a fan-out batch { ciphertext, recipients: [{ to_device, access }] }.
//
// `access` is { signed: "<Ed25519 signature, base64>" } (LIME-139: no user token needed; the server learns nothing about the sender) or
// { identified: true } (a user token is required; the item records the sender, so a stranger's first message can land in Requests). The older
// { sealed: "<access_key>" } was removed in LIME-166: it gets the same opaque 403 as any missing proof. The server stores one item per
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
import { fromBase64, isUuid, sha256, toHex } from "../_shared/bytes.ts";
import { type Access, accessDenied, loadAccess, sealedRow, storeRows, verifySealed } from "../_shared/access.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

type Recipient = { to_device: string; access: { signed?: unknown; identified?: unknown } };

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
    // Sealed (signed). A wrong signature, a missing proof (the removed access key included) and an unknown device all look the same: 403.
    // (A revoked device is the same without `expect`; with it, the proof is checked first and a revoked device is then reported, to the
    // holder of the key only.)
    if (!device) throw accessDenied("unknown_device");
    if (revoked && !checking) throw accessDenied("revoked_device");
    const stored = await loadAccess(db, device.user_id as string, accessByUser);
    const bucketKey = await verifySealed(stored, r.access, id, ciphertextHash);
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
    rows.push(sealedRow(id, ciphertext, ciphertextHash, identified, senderUser));
  }

  // De-duplicate by SHA-256(ciphertext) per recipient device: a repeat is ignored (and the devices that got one are nudged).
  const storedDevices = await storeRows(db, rows);

  return json({ stored: storedDevices.length, duplicates: rows.length - storedDevices.length, checked: checking });
}));
