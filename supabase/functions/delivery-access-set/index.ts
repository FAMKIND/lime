// POST delivery-access-set: stores SHA-256(access_key) for the caller. The server never sees the
// access key itself. Rotation (block) is the same call with a new hash.

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
  const { error } = await admin().from("delivery_access").upsert({
    user_id: userId,
    access_key_hash: toPgBytea(hash),
    updated_at: new Date().toISOString(),
  });
  if (error) throw new HttpError(500, "internal");
  return json({ ok: true });
}));
