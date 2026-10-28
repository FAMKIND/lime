// POST open-feed { since?, limit? } -> { items, cursor }: Discover's index of open posts (LIME-210a, docs/jam.md section 13.3). Signed in, so abuse is rate
// limited per account; METADATA only (title, subtitle, a 240-character excerpt, topics, author, file ids, series, version); the whole signed row comes from
// `open-post-get` by id. `since` is the last `seq` seen: a deleted or taken-down post comes back as `{ post_id, seq, gone: true }` so phones forget it.
// Filters by subject or grade are done on the phone: the server never learns what a person is interested in.

import { admin, rateLimit, requireUser } from "../_shared/db.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  const body = await readJson(req, 2048);
  await rateLimit(`open-feed:${me}`, 1, 120, 60);
  const since = typeof body.since === "number" && Number.isInteger(body.since) && body.since >= 0 ? body.since : 0;
  const limit = typeof body.limit === "number" && Number.isInteger(body.limit) ? Math.min(Math.max(body.limit, 1), 50) : 50;
  const { data, error } = await admin().from("open_posts")
    .select("post_id, author_kind, author_id, jam_id, kind, title, subtitle, excerpt, topics, files, series, preview_of, has_rest, version, created_at, edited_at, deleted_at, taken_down_at, seq")
    .gt("seq", since).order("seq", { ascending: true }).limit(limit);
  if (error) throw new HttpError(500, "internal");
  const items = (data ?? []).map((r) => (r.deleted_at || r.taken_down_at) ? { post_id: r.post_id, seq: r.seq, gone: true } : r);
  return json({ items, cursor: items.length > 0 ? items[items.length - 1].seq : since });
}));
