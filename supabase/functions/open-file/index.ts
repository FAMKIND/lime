// POST open-file { action, ... }: the public file class for open posts (LIME-210a, docs/api-v2.md section 17).
//   put    { file_id, size, mime } -> { url }: a signed upload URL (replaces my file of that id); the writer's open storage quota applies.
//   commit { file_id }             -> { size, public_url }: verifies the upload; the file is then readable by anyone at `public_url` (no session).
//   delete { file_id }             -> { ok }: removes my file (a file of a published post goes with the post).
// The bytes are NOT encrypted: this is for posts the writer chose to make open. Nothing here reads them.

import { admin, rateLimit, requireUser } from "../_shared/db.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { OPEN_BUCKET, objectSize, openConfig, openFileUrl, removeObject, signedUpload } from "../_shared/storage.ts";
import { requireOpenPostsEnabled } from "../_shared/openPosts.ts";

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  const body = await readJson(req, 4096);
  await rateLimit(`open-file:${me}`, 1, 120, 60);
  if (!isUuid(body.file_id)) throw new HttpError(400, "bad_request", "file_id must be a UUID.");
  const id = (body.file_id as string).toLowerCase();
  const db = admin();
  const { data: existing } = await db.from("open_files").select("owner, size, post_id, committed_at").eq("id", id).maybeSingle();
  if (existing && existing.owner !== me) throw new HttpError(409, "id_taken", "That id is in use.");

  switch (body.action) {
    case "put": {
      await requireOpenPostsEnabled();
      const size = body.size;
      if (typeof size !== "number" || !Number.isInteger(size) || size < 1 || size > openConfig.maxFileBytes()) throw new HttpError(400, "bad_request", "That file is too large.");
      const mime = typeof body.mime === "string" && /^[a-z]+\/[a-z0-9.+-]+$/i.test(body.mime) ? body.mime.toLowerCase() : "";
      if (!mime) throw new HttpError(400, "bad_request", "mime is required.");
      const { data: rows, error } = await db.from("open_files").select("size").eq("owner", me).neq("id", id);
      if (error) throw new HttpError(500, "internal");
      const used = (rows ?? []).reduce((sum, r) => sum + Number(r.size), 0);
      if (used + size > openConfig.quotaBytes()) throw new HttpError(413, "quota", "You have reached your open storage limit.");
      const { error: saveError } = await db.from("open_files").upsert({ id, owner: me, size, mime, committed_at: null, post_id: existing?.post_id ?? null }, { onConflict: "id" });
      if (saveError) throw new HttpError(500, "internal");
      return json({ url: (await signedUpload(OPEN_BUCKET, id)).url });
    }
    case "commit": {
      if (!existing) throw new HttpError(404, "not_found", "No such file.");
      const size = await objectSize(OPEN_BUCKET, id);
      if (size === null || size < 1) throw new HttpError(409, "not_uploaded", "Upload the file first.");
      if (size > existing.size) {
        await removeObject(OPEN_BUCKET, id);
        await db.from("open_files").delete().eq("id", id);
        throw new HttpError(413, "too_large", "The file is larger than declared.");
      }
      const { error } = await db.from("open_files").update({ size, committed_at: new Date().toISOString() }).eq("id", id);
      if (error) throw new HttpError(500, "internal");
      return json({ size, public_url: openFileUrl(id) });
    }
    case "delete": {
      if (!existing) return json({ ok: true });
      await removeObject(OPEN_BUCKET, id);
      await db.from("open_files").delete().eq("id", id);
      return json({ ok: true });
    }
    default:
      throw new HttpError(400, "bad_request", "Unknown action.");
  }
}));
