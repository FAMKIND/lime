// POST mesh-drop { header, payload }: a phone that carried a mesh packet and reached the internet hands it to the server (LIME-140).
//
// `header` is the packet's sealed routing header (base64): { to_device, access: { signed } } sealed to the server's mesh public key, so the
// phone that carries and uploads it cannot read who it is for, and `payload` (base64) is exactly the ciphertext `send` would store for that
// recipient device. The server opens the header with MESH_ROUTING_SECRET_KEY and then runs the same access check and the same store as
// `send` for that one recipient device (shared code in `_shared/access.ts`: the signature binds the ciphertext and the device, so a relay
// cannot swap the payload or redirect it). **No session** (LIME-157): the sender's proof is the authority, so the server never learns which
// account carried the packet; an Authorization header, if one is sent anyway, is never read. Limits: per recipient (the `send:access:` bucket)
// and per caller address as a KEYED HASH bucket (`_shared/ipbucket.ts`, never the address). De-duplicated by SHA-256(payload) per device as
// `send` does. Logs nothing identifying. 503 not_configured until the secret exists.

import { admin, config, rateLimit } from "../_shared/db.ts";
import { fromBase64, isUuid, sha256, toHex } from "../_shared/bytes.ts";
import { accessDenied, loadAccess, sealedRow, storeRows, verifySealed } from "../_shared/access.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { openRoutingHeader, routingKeysFromEnv } from "../_shared/mesh.ts";
import { ipBucket } from "../_shared/ipbucket.ts";

const MAX_HEADER_BYTES = 1024;

function bytesOf(value: unknown, what: string, max: number): Uint8Array {
  try {
    const bytes = fromBase64(String(value));
    if (bytes.length === 0 || bytes.length > max) throw new Error();
    return bytes;
  } catch {
    throw new HttpError(400, "bad_request", `${what} must be base64 and not empty or too large.`);
  }
}

Deno.serve(handler(async (req) => {
  const keys = routingKeysFromEnv();
  if (keys.size === 0) throw new HttpError(503, "not_configured", "The mesh is not set up on this server yet.");
  const body = await readJson(req, 512 * 1024);
  const header = bytesOf(body.header, "header", MAX_HEADER_BYTES);
  const payload = bytesOf(body.payload, "payload", config.maxItemBytes());
  // Before any cryptography: the caller's address, as a keyed-hash bucket (a generous cap, since many relays share a school network).
  await rateLimit(await ipBucket(req, "mesh-drop"), 1, 120, 60);

  // Only the server can open the header; anything that does not open, or does not say what a header must, is the same 403 as a wrong proof.
  const opened = await openRoutingHeader(keys, header);
  if (!opened) throw accessDenied("header_unopenable");
  let routing: { to_device?: unknown; access?: { signed?: unknown } };
  try {
    routing = JSON.parse(new TextDecoder().decode(opened));
  } catch {
    throw accessDenied("header_fields");
  }
  const toDevice = typeof routing.to_device === "string" && isUuid(routing.to_device) ? routing.to_device.toLowerCase() : null;
  if (!toDevice || typeof routing.access?.signed !== "string") throw accessDenied("header_fields");

  const db = admin();
  const { data: device } = await db.from("devices").select("device_id, user_id, revoked_at").eq("device_id", toDevice).maybeSingle();
  if (!device) throw accessDenied("unknown_device");
  if (device.revoked_at !== null) throw accessDenied("revoked_device");
  const payloadHash = await sha256(payload);
  const stored = await loadAccess(db, device.user_id as string, new Map());
  const bucketKey = await verifySealed(stored, { signed: routing.access.signed }, toDevice, payloadHash, false);
  await rateLimit(`send:access:${toHex(bucketKey)}`, 1, config.sendPerMinute(), 60);

  const storedDevices = await storeRows(db, [sealedRow(toDevice, payload, payloadHash)]);
  return json({ stored: storedDevices.length, duplicates: 1 - storedDevices.length });
}));
