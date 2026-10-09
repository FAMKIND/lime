// POST attachment { action, ... }: encrypted attachments, uploaded and fetched in chunks (LIME-98c, api-v2.md section 6).
//   put    { attachment_id, size, chunks, recipients } -> { urls: { "<n>": signedUploadUrl } } for the chunks not uploaded yet
//          (call it again with the same id to resume: it returns only what is missing).
//   commit { attachment_id }                            -> verifies every chunk is there and not larger than declared.
//   get    { attachment_id }                            -> { chunks, urls: [signedDownloadUrl] }; counts the caller as a recipient.
//   share  { attachment_id, recipients }                -> a forward (LIME-106): the same encrypted file for `recipients` more people.
//                                                          Anyone who knows the id may (it is a capability, like `get`).
//   delete { attachment_id }                            -> removes it (the sender only).
// Everything stored is ciphertext. The id is a capability (whoever knows it can fetch the ciphertext, which is useless
// without the key that travels inside the encrypted message). Deleted once `recipients` different people have fetched
// it (an hour later, so a download in progress finishes), or 30 days after upload, by the sweep (`blob-sweep`).

import { admin, rateLimit, requireUser } from "../_shared/db.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { BLOB_BUCKET, blobConfig, removeObject, signedDownload, signedUpload } from "../_shared/storage.ts";
import { attachmentConfig, chunkPath, listChunks } from "../_shared/attachments.ts";

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  const body = await readJson(req);
  await rateLimit(`attachment:${me}`, 1, attachmentConfig.perMinute(), 60);
  const db = admin();
  if (!isUuid(body.attachment_id)) throw new HttpError(400, "bad_request", "attachment_id must be a UUID.");
  const id = (body.attachment_id as string).toLowerCase();
  const { data: row } = await db.from("attachments").select("*").eq("id", id).maybeSingle();
  if (body.action !== "get" && body.action !== "share" && row && row.owner !== me) throw new HttpError(409, "id_taken", "That id is in use.");

  switch (body.action) {
    case "put": {
      const { size, chunks, recipients } = body;
      const whole = (v: unknown, lo: number, hi: number) => typeof v === "number" && Number.isInteger(v) && v >= lo && v <= hi;
      if (!whole(size, 1, attachmentConfig.maxBytes()) || !whole(chunks, 1, 60) || !whole(recipients, 1, 100)) {
        throw new HttpError(400, "bad_request", "That file is too large.");
      }
      if ((size as number) < (chunks as number)) throw new HttpError(400, "bad_request", "Bad chunk count.");
      if (row && (row.size !== size || row.chunks !== chunks)) throw new HttpError(409, "id_taken", "That id is in use.");
      if (!row) {
        const { data: mine, error } = await db.from("attachments").select("size").eq("owner", me);
        if (error) throw new HttpError(500, "internal");
        const used = (mine ?? []).reduce((sum, r) => sum + Number(r.size), 0);
        if ((mine ?? []).length + 1 > attachmentConfig.quotaCount() || used + (size as number) > attachmentConfig.quotaBytes()) {
          throw new HttpError(413, "quota", "You have reached your storage limit.");
        }
        const { error: saveError } = await db.from("attachments").insert({ id, owner: me, size, chunks, recipients });
        if (saveError) throw new HttpError(500, "internal");
      } else if (row.committed_at) {
        return json({ urls: {} });   // already complete
      }
      const have = await listChunks(id);
      const urls: Record<string, string> = {};
      for (let n = 0; n < (chunks as number); n++) {
        if (!have.has(n)) urls[String(n)] = (await signedUpload(BLOB_BUCKET, chunkPath(id, n))).url;
      }
      return json({ urls });
    }
    case "commit": {
      if (!row) throw new HttpError(404, "not_found", "No such attachment.");
      const have = await listChunks(id);
      let total = 0;
      for (let n = 0; n < row.chunks; n++) {
        const size = have.get(n);
        if (size === undefined || size < 1) throw new HttpError(409, "not_uploaded", "Upload every chunk first.");
        total += size;
      }
      if (total > row.size) {
        await removeAttachment(id, row.chunks);
        throw new HttpError(413, "too_large", "The file is larger than declared.");
      }
      const { error } = await db.from("attachments").update({ committed_at: new Date().toISOString() }).eq("id", id);
      if (error) throw new HttpError(500, "internal");
      return json({ size: total });
    }
    case "get": {
      if (!row || !row.committed_at || new Date(row.expires_at).getTime() < Date.now()) throw new HttpError(404, "not_found", "No such attachment.");
      const urls: string[] = [];
      for (let n = 0; n < row.chunks; n++) urls.push(await signedDownload(BLOB_BUCKET, chunkPath(id, n)));
      if (row.owner !== me) {
        await db.from("attachment_fetches").upsert({ attachment_id: id, user_id: me }, { onConflict: "attachment_id,user_id" });
        const { count } = await db.from("attachment_fetches").select("*", { count: "exact", head: true }).eq("attachment_id", id);
        if ((count ?? 0) >= row.recipients) {
          // Everyone has it: delete soon (an hour, so a download that has started can finish).
          const soon = new Date(Date.now() + 3600_000).toISOString();
          if (new Date(row.expires_at).getTime() > Date.parse(soon)) await db.from("attachments").update({ expires_at: soon }).eq("id", id);
        }
      }
      return json({ chunks: row.chunks, urls });
    }
    case "share": {
      const extra = body.recipients;
      if (typeof extra !== "number" || !Number.isInteger(extra) || extra < 1 || extra > 100) throw new HttpError(400, "bad_request", "Bad recipients.");
      if (!row || !row.committed_at || new Date(row.expires_at).getTime() < Date.now()) throw new HttpError(404, "not_found", "No such attachment.");
      // More people will fetch it, so it stays: at least a week from now, but never past 30 days after it was uploaded.
      const week = Date.now() + 7 * 86_400_000;
      const cap = new Date(row.created_at).getTime() + 30 * 86_400_000;
      const expires = new Date(Math.min(cap, Math.max(new Date(row.expires_at).getTime(), week))).toISOString();
      const { error } = await db.from("attachments").update({ recipients: Math.min(100, row.recipients + extra), expires_at: expires }).eq("id", id);
      if (error) throw new HttpError(500, "internal");
      return json({ ok: true });
    }
    case "delete": {
      if (row) await removeAttachment(id, row.chunks);
      return json({ ok: true });
    }
    default:
      throw new HttpError(400, "bad_request", "Unknown action.");
  }
}));

async function removeAttachment(id: string, chunks: number) {
  for (let n = 0; n < Math.max(chunks, 1); n++) await removeObject(BLOB_BUCKET, chunkPath(id, n));
  const { error } = await admin().from("attachments").delete().eq("id", id);
  if (error) throw new HttpError(500, "internal");
}
