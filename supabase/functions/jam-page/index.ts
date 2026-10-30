// POST jam-page { action, ... }: a jam's public page (LIME-187, docs/jam.md section 7). The page is the ONLY part of a jam the server can read: a title,
// an about line, topics and a post count the writer chooses to show. Posts are end-to-end encrypted and never come here.
//   set  { jam_id, title, about, topics[], post_count, subscriber_count, has_community? } -> { ok }: creates or updates MY jam's page (the count is public, with the page;
//        has_community is the one public bit of a community chat, LIME-210g).
//   get  { jam_id }                                      -> { jam }: any signed-in user.
//   end  { jam_id }                                      -> { ok, removed }: marks the page ended and deletes all of the jam's posts (the ciphertext).
//   picture_put { jam_id, size } -> { url }: a signed upload URL for MY jam's picture (JPEG, at most 1 MiB; LIME-194). Public, like the title: the server and any signed-in teacher can see it.
//   picture_commit { jam_id }    -> { version }: verifies the upload and makes it visible (`picture_version` on the page).
//   picture_get { jam_id }       -> { url, version }: a signed download URL, any signed-in user (404 if none).
//   picture_remove { jam_id }    -> { ok }: deletes it. Ending a jam deletes it too.
//   cover_put { jam_id, size } / cover_commit / cover_get / cover_remove: a public cover (LIME-258), like the picture, under `jam-cover-<jam_id>.jpg`; `tone_set { jam_id, tone }` sets the colour (0 to 7, or null).
//   by_writer { writer_id }                              -> { jam, others }: that teacher's own (oldest live, not ended) page, or { jam: null }, and their other live pages (bands), oldest first, at most 20. Any signed-in user, the same trust
//                                                           as reading their profile (the server learns that this account looked).

import { admin, requireUser } from "../_shared/db.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { AVATAR_BUCKET, BLOB_BUCKET, MAX_AVATAR_BYTES, objectSize, removeObject, signedDownload, signedUpload } from "../_shared/storage.ts";
import { rateLimit } from "../_shared/db.ts";

/** A jam's picture lives beside the profile photos, under the jam's id (a user id is a UUID without this prefix, so the keys never meet). */
const pictureKey = (jamId: string) => `jam-${jamId}.jpg`;
const coverKey = (jamId: string) => `jam-cover-${jamId}.jpg`;

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
    const { data, error } = await admin().from("jams").select("jam_id, writer_id, title, about, topics, post_count, subscriber_count, has_community, picture_version, tone, cover_version, created_at")
      .eq("writer_id", (body.writer_id as string).toLowerCase()).is("ended_at", null).is("taken_down_at", null).order("created_at", { ascending: true }).limit(21);
    if (error) throw new HttpError(500, "internal");
    // LIME-254b: `jam` is the writer's own jam (the oldest); `others` are their other live pages (bands), oldest first, at most 20.
    return json({ jam: data?.[0] ?? null, others: data?.slice(1) ?? [] });
  }
  if (!isUuid(body.jam_id)) throw new HttpError(400, "bad_request", "jam_id must be a UUID.");
  const jamId = (body.jam_id as string).toLowerCase();
  const db = admin();
  const { data: existing } = await db.from("jams").select("jam_id, writer_id, ended_at").eq("jam_id", jamId).maybeSingle();
  if (body.action !== "get" && body.action !== "picture_get" && body.action !== "cover_get" && existing && existing.writer_id !== me) throw new HttpError(409, "id_taken", "That jam belongs to someone else.");

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
        jam_id: jamId, writer_id: me, title: clean(body.title, 60), about: clean(body.about ?? "", 500, true), topics, post_count: count, subscriber_count: subscribers, has_community: body.has_community === true,
      }, { onConflict: "jam_id" });
      if (error) throw new HttpError(500, "internal");
      return json({ ok: true });
    }
    case "get": {
      const { data, error } = await db.from("jams").select("jam_id, writer_id, title, about, topics, post_count, subscriber_count, has_community, picture_version, tone, cover_version, created_at, ended_at, taken_down_at").eq("jam_id", jamId).maybeSingle();
      if (error) throw new HttpError(500, "internal");
      if (!data) throw new HttpError(404, "not_found", "No such jam.");
      if (data.taken_down_at) throw new HttpError(410, "taken_down", "That jam was taken down.");
      return json({ jam: data });
    }
    case "picture_put": {
      if (!existing || existing.ended_at) throw new HttpError(404, "not_found", "No such jam.");
      if (typeof body.size !== "number" || !Number.isInteger(body.size) || body.size < 1 || body.size > MAX_AVATAR_BYTES) {
        throw new HttpError(400, "bad_request", "Your picture is too large.");
      }
      return json({ url: (await signedUpload(AVATAR_BUCKET, pictureKey(jamId))).url });
    }
    case "picture_commit": {
      if (!existing || existing.ended_at) throw new HttpError(404, "not_found", "No such jam.");
      const size = await objectSize(AVATAR_BUCKET, pictureKey(jamId));
      if (size === null || size < 1) throw new HttpError(409, "not_uploaded", "Upload the picture first.");
      if (size > MAX_AVATAR_BYTES) {
        await removeObject(AVATAR_BUCKET, pictureKey(jamId));
        throw new HttpError(413, "too_large", "Your picture is too large.");
      }
      const version = Date.now();
      const { error } = await db.from("jams").update({ picture_version: version }).eq("jam_id", jamId);
      if (error) throw new HttpError(500, "internal");
      return json({ version });
    }
    case "picture_get": {
      const { data } = await db.from("jams").select("picture_version, taken_down_at").eq("jam_id", jamId).maybeSingle();
      if (!data || data.picture_version === null || data.taken_down_at) throw new HttpError(404, "not_found", "Nothing public.");
      return json({ url: await signedDownload(AVATAR_BUCKET, pictureKey(jamId)), version: data.picture_version });
    }
    case "picture_remove": {
      if (!existing) throw new HttpError(404, "not_found", "No such jam.");
      await removeObject(AVATAR_BUCKET, pictureKey(jamId));
      const { error } = await db.from("jams").update({ picture_version: null }).eq("jam_id", jamId);
      if (error) throw new HttpError(500, "internal");
      return json({ ok: true });
    }
    case "tone_set": {
      // The band's colour (LIME-258): 0 to 7, or null for the default (from the jam id, chosen by the app).
      if (!existing || existing.ended_at) throw new HttpError(404, "not_found", "No such jam.");
      const tone = body.tone ?? null;
      if (tone !== null && (typeof tone !== "number" || !Number.isInteger(tone) || tone < 0 || tone > 7)) throw new HttpError(400, "bad_request", "Bad colour.");
      const { error } = await db.from("jams").update({ tone }).eq("jam_id", jamId);
      if (error) throw new HttpError(500, "internal");
      return json({ ok: true });
    }
    case "cover_put": {
      if (!existing || existing.ended_at) throw new HttpError(404, "not_found", "No such jam.");
      if (typeof body.size !== "number" || !Number.isInteger(body.size) || body.size < 1 || body.size > MAX_AVATAR_BYTES) {
        throw new HttpError(400, "bad_request", "Your cover is too large.");
      }
      return json({ url: (await signedUpload(AVATAR_BUCKET, coverKey(jamId))).url });
    }
    case "cover_commit": {
      if (!existing || existing.ended_at) throw new HttpError(404, "not_found", "No such jam.");
      const size = await objectSize(AVATAR_BUCKET, coverKey(jamId));
      if (size === null || size < 1) throw new HttpError(409, "not_uploaded", "Upload the cover first.");
      if (size > MAX_AVATAR_BYTES) {
        await removeObject(AVATAR_BUCKET, coverKey(jamId));
        throw new HttpError(413, "too_large", "Your cover is too large.");
      }
      const version = Date.now();
      const { error } = await db.from("jams").update({ cover_version: version }).eq("jam_id", jamId);
      if (error) throw new HttpError(500, "internal");
      return json({ version });
    }
    case "cover_get": {
      const { data } = await db.from("jams").select("cover_version, taken_down_at").eq("jam_id", jamId).maybeSingle();
      if (!data || data.cover_version === null || data.taken_down_at) throw new HttpError(404, "not_found", "Nothing public.");
      return json({ url: await signedDownload(AVATAR_BUCKET, coverKey(jamId)), version: data.cover_version });
    }
    case "cover_remove": {
      if (!existing) throw new HttpError(404, "not_found", "No such jam.");
      await removeObject(AVATAR_BUCKET, coverKey(jamId));
      const { error } = await db.from("jams").update({ cover_version: null }).eq("jam_id", jamId);
      if (error) throw new HttpError(500, "internal");
      return json({ ok: true });
    }
    case "end": {
      if (!existing) throw new HttpError(404, "not_found", "No such jam.");
      const { data: posts, error } = await db.from("blobs").select("id").eq("jam_id", jamId).eq("owner", me).limit(5000);
      if (error) throw new HttpError(500, "internal");
      for (const row of posts ?? []) {
        await removeObject(BLOB_BUCKET, row.id);
        await db.from("blobs").delete().eq("id", row.id);
      }
      await removeObject(AVATAR_BUCKET, pictureKey(jamId));
      await removeObject(AVATAR_BUCKET, coverKey(jamId));
      const { error: endError } = await db.from("jams").update({ ended_at: new Date().toISOString(), post_count: 0, picture_version: null, cover_version: null }).eq("jam_id", jamId);
      if (endError) throw new HttpError(500, "internal");
      return json({ ok: true, removed: (posts ?? []).length });
    }
    default:
      throw new HttpError(400, "bad_request", "Unknown action.");
  }
}));
