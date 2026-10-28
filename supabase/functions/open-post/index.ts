// POST open-post { action, ... }: publish, edit and delete an OPEN post (LIME-210a, docs/api-v2.md section 17, docs/jam.md section 13).
//   publish { payload, signature, cert } -> { post_id, version, seq }: (a post I deleted can be published again: its version continues) `payload` is the exact JSON text the writer's device signed (label "lime-open-post-v1\n"
//            + the text); `cert` is that device's certificate (device_id, identity_key, signing_key, master_key, master_signature). Refused while the server
//            flag `open_posts_enabled` is off; refused for a forged or another writer's row; the files it names must be MY committed open files.
//   edit    { payload, signature, cert } -> { post_id, version, seq }: the next version (version = old + 1) of MY post; files no longer named are removed.
//   delete  { post_id }                  -> { ok, seq }: a tombstone (so a phone with an older cursor learns of it); the row's text and the public files go.
// Limits: a burst (10 a minute), and in an account's first week 10 a day; files count against the open storage quota (2 GiB).

import { admin, rateLimit, requireUser } from "../_shared/db.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { OPEN_BUCKET, openConfig, removeObject } from "../_shared/storage.ts";
import { excerptOf, requireOpenPostsEnabled, verifyRow } from "../_shared/openPosts.ts";

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  const body = await readJson(req, 300 * 1024);
  const db = admin();

  if (body.action === "delete") {
    if (!isUuid(body.post_id)) throw new HttpError(400, "bad_request", "post_id must be a UUID.");
    const id = (body.post_id as string).toLowerCase();
    const { data: row } = await db.from("open_posts").select("author_id, files, deleted_at").eq("post_id", id).maybeSingle();
    if (!row) throw new HttpError(404, "not_found", "No such post.");
    if (row.author_id !== me) throw new HttpError(403, "not_author", "That post is not yours.");
    await removeFiles(row.files as string[]);
    const { data: seq } = await db.rpc("nextval_open_posts");
    const { error } = await db.from("open_posts").update({ deleted_at: new Date().toISOString(), payload: null, signature: null, cert: null, files: [], title: "", subtitle: "", excerpt: "", seq }).eq("post_id", id);
    if (error) throw new HttpError(500, "internal");
    return json({ ok: true, seq });
  }
  if (body.action !== "publish" && body.action !== "edit") throw new HttpError(400, "bad_request", "Unknown action.");

  await requireOpenPostsEnabled();
  await rateLimit(`open-post:${me}`, 1, openConfig.burstPerMinute(), 60);
  const payloadText = body.payload as string;
  const row = await verifyRow(me, payloadText, body.signature, body.cert);
  // The jam must be mine and not ended.
  const { data: jam } = await db.from("jams").select("writer_id, ended_at").eq("jam_id", row.jam_id).maybeSingle();
  if (!jam || jam.writer_id !== me || jam.ended_at) throw new HttpError(403, "not_your_jam", "That jam is not yours.");
  const { data: existing } = await db.from("open_posts").select("author_id, version, files, deleted_at, taken_down_at").eq("post_id", row.post_id).maybeSingle();

  // A tombstone of mine can be published again (Subscribers -> Everyone -> Subscribers -> Everyone): the version continues from the tombstone's.
  const republish = body.action === "publish" && existing?.deleted_at && existing.author_id === me && !existing.taken_down_at;
  if (body.action === "publish") {
    if (existing && !republish) throw new HttpError(409, "id_taken", "That post already exists.");
    if (row.version !== (republish ? existing!.version + 1 : 1)) throw new HttpError(400, "bad_request", republish ? "The version must be the next one." : "A new post is version 1.");
    // An account's first week: at most N open posts a day (the anti-spam guard).
    const { data: user } = await db.auth.admin.getUserById(me);
    const ageDays = user?.user ? (Date.now() - new Date(user.user.created_at).getTime()) / 86_400_000 : 99;
    if (ageDays < 7) {
      const since = new Date(Date.now() - 86_400_000).toISOString();
      const { count } = await db.from("open_posts").select("post_id", { count: "exact", head: true }).eq("author_id", me).gte("created_at", since);
      if ((count ?? 0) >= openConfig.firstWeekPerDay()) throw new HttpError(429, "first_week_limit", "A new account can make 10 open posts a day for its first week.");
    }
  } else {
    if (!existing || existing.deleted_at || existing.taken_down_at) throw new HttpError(404, "not_found", "No such post.");
    if (existing.author_id !== me) throw new HttpError(403, "not_author", "That post is not yours.");
    if (row.version !== existing.version + 1) throw new HttpError(409, "version", "The version must be the next one.");
  }

  // The files it names are mine, committed, and not another post's.
  const ids = row.attachments.map((a) => a.id.toLowerCase());
  if (ids.length > 0) {
    const { data: files } = await db.from("open_files").select("id, owner, post_id, committed_at").in("id", ids);
    const ok = (files ?? []).length === new Set(ids).size && (files ?? []).every((f) => f.owner === me && f.committed_at && (f.post_id === null || f.post_id === row.post_id));
    if (!ok) throw new HttpError(400, "bad_files", "A file is missing, not uploaded, or not yours.");
  }
  const { data: seq } = await db.rpc("nextval_open_posts");
  const fields = {
    post_id: row.post_id, author_kind: "person", author_id: me, jam_id: row.jam_id, kind: row.kind, title: row.title, subtitle: row.subtitle,
    excerpt: excerptOf(row.markdown), topics: row.topics, files: ids, series: row.series ?? null, preview_of: row.preview_of, has_rest: row.has_rest ?? false,
    version: row.version, payload: payloadText, signature: body.signature as string, cert: body.cert, seq,
  };
  if (body.action === "publish") {
    const { error } = republish
      ? await db.from("open_posts").update({ ...fields, deleted_at: null, edited_at: new Date().toISOString() }).eq("post_id", row.post_id)
      : await db.from("open_posts").insert(fields);
    if (error) throw new HttpError(500, "internal");
  } else {
    const { error } = await db.from("open_posts").update({ ...fields, edited_at: new Date().toISOString() }).eq("post_id", row.post_id);
    if (error) throw new HttpError(500, "internal");
    await removeFiles(((existing!.files as string[]) ?? []).filter((id) => !ids.includes(id)));
  }
  if (ids.length > 0) await db.from("open_files").update({ post_id: row.post_id }).in("id", ids);
  return json({ post_id: row.post_id, version: row.version, seq }, body.action === "publish" ? 201 : 200);
}));

async function removeFiles(ids: string[]): Promise<void> {
  const db = admin();
  for (const id of ids) {
    try {
      await removeObject(OPEN_BUCKET, id);
    } catch { /* already gone */ }
    await db.from("open_files").delete().eq("id", id);
  }
}
