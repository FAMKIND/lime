// POST send: a fan-out batch { ciphertext, recipients: [{ to_device, access }] }.
//
// `access` is { sealed: "<access_key, base64>" } (no user token needed; the server learns nothing
// about the sender) or { identified: true } (a user token is required; the item records the
// sender, so a stranger's first message can land in Requests). The server stores one item per
// recipient device, de-duplicated by SHA-256(ciphertext) per device, then nudges the device's
// Realtime channel (a private channel only its owner may join) with { type: "new" } (no content).
//
// Nothing here logs ciphertext, keys, access keys or tokens.

import { admin, config, rateLimit, requireUser } from "../_shared/db.ts";
import { constantTimeEqual, fromBase64, fromPgBytea, isUuid, sha256, toHex, toPgBytea } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

type Recipient = { to_device: string; access: { sealed?: unknown; identified?: unknown } };

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

  const list = recipients as Recipient[];
  for (const r of list) {
    if (!r || !isUuid(r.to_device) || typeof r.access !== "object" || r.access === null) {
      throw new HttpError(400, "bad_request", "Each recipient needs a to_device UUID and an access.");
    }
  }

  // A user token is needed only when some recipient is sent identified.
  const anyIdentified = list.some((r) => r.access.identified === true);
  const senderUser = anyIdentified ? await requireUser(req) : null;

  const db = admin();
  const deviceIds = [...new Set(list.map((r) => r.to_device.toLowerCase()))];
  const { data: devices, error: devicesError } = await db
    .from("devices").select("device_id, user_id, revoked_at").in("device_id", deviceIds);
  if (devicesError) throw new HttpError(500, "internal");
  const deviceById = new Map((devices ?? []).map((d) => [d.device_id as string, d]));

  // Check every recipient's access before storing anything: all or nothing.
  const accessHashByUser = new Map<string, Uint8Array | null>();
  const sealedCostByKey = new Map<string, number>(); // bucket -> items
  let identifiedItems = 0;
  for (const r of list) {
    const device = deviceById.get(r.to_device.toLowerCase());
    const unknown = !device || device.revoked_at !== null;
    if (r.access.identified === true) {
      if (unknown) throw new HttpError(404, "unknown_device", "A recipient device is unknown or revoked.");
      identifiedItems++;
      continue;
    }
    // Sealed. A wrong key, a missing key and an unknown device all look the same: 403.
    const denied = () => new HttpError(403, "access_denied", "The access key was not accepted.");
    if (unknown || typeof r.access.sealed !== "string") throw denied();
    let presented: Uint8Array;
    try {
      presented = fromBase64(r.access.sealed);
    } catch {
      throw denied();
    }
    if (presented.length !== 16) throw denied();
    const presentedHash = await sha256(presented);
    if (!accessHashByUser.has(device.user_id)) {
      const { data } = await db.from("delivery_access").select("access_key_hash").eq("user_id", device.user_id).maybeSingle();
      accessHashByUser.set(device.user_id, data ? fromPgBytea(data.access_key_hash as string) : null);
    }
    const stored = accessHashByUser.get(device.user_id);
    if (!stored || !constantTimeEqual(stored, presentedHash)) throw denied();
    const bucket = `send:access:${toHex(presentedHash)}`;
    sealedCostByKey.set(bucket, (sealedCostByKey.get(bucket) ?? 0) + 1);
  }

  // Rate limits: recipient-items per minute, per user (identified) or per access key (sealed).
  if (identifiedItems > 0 && senderUser) {
    await rateLimit(`send:user:${senderUser}`, identifiedItems, config.sendPerMinute(), 60);
  }
  for (const [bucket, cost] of sealedCostByKey) {
    await rateLimit(bucket, cost, config.sendPerMinute(), 60);
  }

  const ciphertextHash = await sha256(ciphertext);
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
  return json({ stored: storedDevices.length, duplicates: rows.length - storedDevices.length });
}));
