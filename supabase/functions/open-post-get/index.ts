// POST open-post-get { post_id } -> { post }: the whole signed row of an open post, WITHOUT a session (LIME-210a; like `jam-blob-get`): an open post is
// public by the writer's choice, so the server does not tie the read to an account. Rate-limited per network address. A deleted post is 404 (a tombstone
// carries no text) and a taken-down one is 410. The phone verifies the signature and certificate itself.

import { admin, rateLimit } from "../_shared/db.ts";
import { clientIp } from "../_shared/auth.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { openConfig, openFileUrl } from "../_shared/storage.ts";

Deno.serve(handler(async (req) => {
  const body = await readJson(req, 2048);
  await rateLimit(`open-post-get:${clientIp(req)}`, 1, openConfig.getPerMinute(), 60);
  if (!isUuid(body.post_id)) throw new HttpError(404, "not_found", "No such post.");
  const { data, error } = await admin().from("open_posts")
    .select("post_id, author_kind, author_id, jam_id, kind, files, version, payload, signature, cert, created_at, edited_at, deleted_at, taken_down_at, seq")
    .eq("post_id", (body.post_id as string).toLowerCase()).maybeSingle();
  if (error) throw new HttpError(500, "internal");
  if (!data || data.deleted_at) throw new HttpError(404, "not_found", "No such post.");
  if (data.taken_down_at) throw new HttpError(410, "taken_down", "That post was taken down.");
  return json({ post: { ...data, file_urls: (data.files as string[]).map((id) => ({ id, url: openFileUrl(id) })) } });
}));
