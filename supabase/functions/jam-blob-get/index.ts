// POST jam-blob-get { blob_id } -> { url }: a short-lived signed download URL for a jam post (LIME-187, docs/jam.md).
//
// NO SESSION. The post is ciphertext only, found by its 128-bit random id (a capability: whoever holds the id from the encrypted post notice may
// fetch it), so the server cannot tie a download to an account. What the server sees is the request's network address. Rate-limited per address
// (the bucket is the address alone: no blob id is ever part of a limiter key, a log line or a stored row of this function). A wrong, expired or
// unknown id is the same 404, and the answer takes about the same time either way.
//
// Nothing here logs the id, the address or the body.

import { admin, rateLimit } from "../_shared/db.ts";
import { clientIp } from "../_shared/auth.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { BLOB_BUCKET, blobConfig, signedDownload } from "../_shared/storage.ts";

const FLOOR_MS = 120;

Deno.serve(handler(async (req) => {
  const started = performance.now();
  const body = await readJson(req, 4096);
  await rateLimit(`jam-blob-get:${clientIp(req)}`, 1, blobConfig.jamGetPerMinute(), 60);
  let url: string | null = null;
  if (isUuid(body.blob_id)) {
    const id = (body.blob_id as string).toLowerCase();
    const { data, error } = await admin().from("blobs").select("id").eq("id", id).eq("class", "jam").not("committed_at", "is", null).maybeSingle();
    if (error) throw new HttpError(500, "internal");
    if (data) {
      try {
        url = await signedDownload(BLOB_BUCKET, id);
      } catch {
        url = null;
      }
    }
  }
  // The same time whether it was found or not (best effort).
  const wait = FLOOR_MS - (performance.now() - started);
  if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
  if (!url) throw new HttpError(404, "not_found", "No such post.");
  return json({ url });
}));
