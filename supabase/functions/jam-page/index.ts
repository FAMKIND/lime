// POST jam-page { action, ... }: a jam's public page (LIME-187, docs/jam.md section 7). The page is the ONLY part of a jam the server can read: a title,
// an about line, topics and a post count the writer chooses to show. Posts are end-to-end encrypted and never come here.
//   set  { jam_id, title, about, topics[], post_count, subscriber_count } -> { ok }: creates or updates MY jam's page (the count is public, with the page).
//   get  { jam_id }                                      -> { jam }: any signed-in user.
//   end  { jam_id }                                      -> { ok, removed }: marks the page ended and deletes all of the jam's posts (the ciphertext).
//   by_writer { writer_id }                              -> { jam }: that teacher's live (not ended) page, or { jam: null }. Any signed-in user, the same trust
//                                                           as reading their profile (the server learns that this account looked).

import { admin, requireUser } from "../_shared/db.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { BLOB_BUCKET, removeObject } from "../_shared/storage.ts";
import { rateLimit } from "../_shared/db.ts";

function clean(value: unknown, max: number, allowEmpty = false): string {
  const text = typeof value === "string" ? value.trim() : "";
  if ((!allowEmpty && text.length === 0) || [...text].length > max) throw new HttpError(400, "bad_request", "That text is empty or too long.");
  return text;
}

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  const body = await readJson(req);
  await rateLimit(`jam-page:${me}`, 1, 120, 60);
  if (body.action === "by_writer") {
    if (!isUuid(body.writer_id)) throw new HttpError(400, "bad_request", "writer_id must be a UUID.");
    const { data, error } = await admin().from("jams").select("jam_id, writer_id, title, about, topics, post_count, subscriber_count, created_at")
      .eq("writer_id", (body.writer_id as string).toLowerCase()).is("ended_at", null).is("taken_down_at", null).order("created_at", { ascending: false }).limit(1);
    if (error) throw new HttpError(500, "internal");
    return json({ jam: data?.[0] ?? null });
  }
  if (!isUuid(body.jam_id)) throw new HttpError(400, "bad_request", "jam_id must be a UUID.");
  const jamId = (body.jam_id as string).toLowerCase();
  const db = admin();
  const { data: existing } = await db.from("jams").select("jam_id, writer_id, ended_at").eq("jam_id", jamId).maybeSingle();
  if (body.action !== "get" && existing && existing.writer_id !== me) throw new HttpError(409, "id_taken", "That jam belongs to someone else.");

  switch (body.action) {
    case "set": {
      if (existing?.ended_at) throw new HttpError(409, "ended", "That jam has ended.");
      const topics = Array.isArray(body.topics) ? body.topics.map((t) => clean(t, 30)) : [];
      const count = body.post_count;
      const subscribers = body.subscriber_count ?? 0;
      if (typeof subscribers !== "number" || !Number.isInteger(subscribers) || subscribers < 0 || subscribers > 1_000_000) throw new HttpError(400, "bad_request", "Bad subscriber count.");
      if (topics.length > 8 || typeof count !== "number" || !Number.isInteger(count) || count < 0 || count > 1_000_000) {
        throw new HttpError(400, "bad_request", "Too many topics, or a bad count.");
      }
      const { error } = await db.from("jams").upsert({
        jam_id: jamId, writer_id: me, title: clean(body.title, 60), about: clean(body.about ?? "", 500, true), topics, post_count: count, subscriber_count: subscribers,
      }, { onConflict: "jam_id" });
      if (error) throw new HttpError(500, "internal");
      return json({ ok: true });
    }
    case "get": {
      const { data, error } = await db.from("jams").select("jam_id, writer_id, title, about, topics, post_count, subscriber_count, created_at, ended_at, taken_down_at").eq("jam_id", jamId).maybeSingle();
      if (error) throw new HttpError(500, "internal");
      if (!data) throw new HttpError(404, "not_found", "No such jam.");
      if (data.taken_down_at) throw new HttpError(410, "taken_down", "That jam was taken down.");
      return json({ jam: data });
    }
    case "end": {
      if (!existing) throw new HttpError(404, "not_found", "No such jam.");
      const { data: posts, error } = await db.from("blobs").select("id").eq("jam_id", jamId).eq("owner", me).limit(5000);
      if (error) throw new HttpError(500, "internal");
      for (const row of posts ?? []) {
        await removeObject(BLOB_BUCKET, row.id);
        await db.from("blobs").delete().eq("id", row.id);
      }
      const { error: endError } = await db.from("jams").update({ ended_at: new Date().toISOString(), post_count: 0 }).eq("jam_id", jamId);
      if (endError) throw new HttpError(500, "internal");
      return json({ ok: true, removed: (posts ?? []).length });
    }
    default:
      throw new HttpError(400, "bad_request", "Unknown action.");
  }
}));
