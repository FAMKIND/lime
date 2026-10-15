// POST delivery-access-set: stores SHA-256(access_key) and, since LIME-139, the PUBLIC key of the Ed25519 pair derived from the delivery key
// (`access_public_key`, 32 bytes base64) for the caller. The server never sees the access key or the delivery key. Rotation (block) is the same
// call with a new hash and a new public key. A call without `access_public_key` (an older build) CLEARS the stored one: a public key left from
// the previous delivery key must never outlive a rotation.

import { admin, requireUser } from "../_shared/db.ts";
import { fromBase64, toPgBytea } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const body = await readJson(req);
  let hash: Uint8Array;
  try {
    hash = fromBase64(String(body.access_key_hash));
    if (hash.length !== 32) throw new Error();
  } catch {
    throw new HttpError(400, "bad_request", "access_key_hash must be a base64 SHA-256 (32 bytes).");
  }
  let publicKey: Uint8Array | null = null;
  if (body.access_public_key !== undefined && body.access_public_key !== null) {
    try {
      publicKey = fromBase64(String(body.access_public_key));
      if (publicKey.length !== 32) throw new Error();
    } catch {
      throw new HttpError(400, "bad_request", "access_public_key must be a base64 Ed25519 public key (32 bytes).");
    }
  }
  const { error } = await admin().from("delivery_access").upsert({
    user_id: userId,
    access_key_hash: toPgBytea(hash),
    access_public_key: publicKey ? toPgBytea(publicKey) : null,
    updated_at: new Date().toISOString(),
  });
  if (error) throw new HttpError(500, "internal");
  return json({ ok: true });
}));
