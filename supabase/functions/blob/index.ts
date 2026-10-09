// POST blob { action, ... }: the store for CIPHERTEXT blobs (LIME-98b, api-v2.md section 6).
//   put    { blob_id, size, expires_in_days? } -> { url }: a signed upload URL (replaces my blob of that id).
//   commit { blob_id }                         -> verifies the upload (size, quota): { size }.
//   get    { blob_id }                         -> { url, version }: a signed download URL, if committed.
//   delete { blob_id }                         -> removes my blob.
// The server holds only bytes it cannot read: the encryption key is never sent here. The id is chosen by
// the client; whoever knows an id can download that ciphertext (it is a capability), only the owner can
// replace or delete it. Uploads are limited per file, per user (bytes and count) and per minute.

import { admin, rateLimit, requireUser } from "../_shared/db.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { BLOB_BUCKET, blobConfig, objectSize, removeObject, signedDownload, signedUpload } from "../_shared/storage.ts";

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  const body = await readJson(req);
  await rateLimit(`blob:${me}`, 1, blobConfig.perMinute(), 60);
  const db = admin();
  if (!isUuid(body.blob_id)) throw new HttpError(400, "bad_request", "blob_id must be a UUID.");
  const id = (body.blob_id as string).toLowerCase();
  const path = `${id}`;
  const { data: existing } = await db.from("blobs").select("owner, size, committed_at").eq("id", id).maybeSingle();
  if (body.action !== "get" && existing && existing.owner !== me) throw new HttpError(409, "id_taken", "That id is in use.");

  switch (body.action) {
    case "put": {
      const size = body.size;
      if (typeof size !== "number" || !Number.isInteger(size) || size < 1 || size > blobConfig.maxBlobBytes()) {
        throw new HttpError(400, "bad_request", "That file is too large.");
      }
      const { data: mine, error } = await db.from("blobs").select("id, size").eq("owner", me).neq("id", id);
      if (error) throw new HttpError(500, "internal");
      const used = (mine ?? []).reduce((sum, row) => sum + row.size, 0);
      if ((mine ?? []).length + 1 > blobConfig.quotaCount() || used + size > blobConfig.quotaBytes()) {
        throw new HttpError(413, "quota", "You have reached your storage limit.");
      }
      const days = typeof body.expires_in_days === "number" && body.expires_in_days > 0 ? Math.min(body.expires_in_days, 365) : null;
      const row = {
        id, owner: me, size, committed_at: null,
        expires_at: days === null ? null : new Date(Date.now() + days * 86_400_000).toISOString(),
      };
      const { error: saveError } = await db.from("blobs").upsert(row, { onConflict: "id" });
      if (saveError) throw new HttpError(500, "internal");
      return json({ url: (await signedUpload(BLOB_BUCKET, path)).url });
    }
    case "commit": {
      if (!existing) throw new HttpError(404, "not_found", "No such blob.");
      const size = await objectSize(BLOB_BUCKET, path);
      if (size === null || size < 1) throw new HttpError(409, "not_uploaded", "Upload the file first.");
      if (size > existing.size) {
        // More bytes than were declared (and counted against the quota): refuse and remove them.
        await removeObject(BLOB_BUCKET, path);
        await db.from("blobs").delete().eq("id", id);
        throw new HttpError(413, "too_large", "The file is larger than declared.");
      }
      const { error } = await db.from("blobs").update({ size, committed_at: new Date().toISOString() }).eq("id", id);
      if (error) throw new HttpError(500, "internal");
      return json({ size });
    }
    case "get": {
      if (!existing || !existing.committed_at) throw new HttpError(404, "not_found", "No such blob.");
      const { data } = await db.from("blobs").select("committed_at, expires_at").eq("id", id).single();
      if (data?.expires_at && new Date(data.expires_at).getTime() < Date.now()) throw new HttpError(404, "not_found", "No such blob.");
      return json({ url: await signedDownload(BLOB_BUCKET, path), version: new Date(data!.committed_at as string).getTime() });
    }
    case "delete": {
      if (!existing) return json({ ok: true });
      await removeObject(BLOB_BUCKET, path);
      const { error } = await db.from("blobs").delete().eq("id", id);
      if (error) throw new HttpError(500, "internal");
      return json({ ok: true });
    }
    default:
      throw new HttpError(400, "bad_request", "Unknown action.");
  }
}));
