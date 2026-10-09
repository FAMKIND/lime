// POST profile-get {}: the signed-in user's own profile, or { profile: null } for a new account.
// POST profile-get { user_id }: another person's PUBLIC fields only (display name, username, school;
// never an email or phone). Someone who hid themselves from search shows only their display name.
// Rate-limited. A person with no profile yet is a 404.

import { admin, config, rateLimit, requireUser } from "../_shared/db.ts";
import { maskEmail } from "../_shared/auth.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  const body = await readJson(req);
  const wanted = body.user_id;
  if (wanted === undefined || wanted === me) {
    const { data, error } = await admin().from("profiles")
      .select("user_id, display_name, username, school, about_emoji, about_text, hide_from_search, photo_visibility, avatar_version").eq("user_id", me).maybeSingle();
    if (error) throw new HttpError(500, "internal");
    // Your own address, masked, for the Account screen (never anyone else's).
    const { data: owner } = await admin().auth.admin.getUserById(me);
    return json({ profile: data ?? null, masked_email: owner?.user?.email ? maskEmail(owner.user.email) : null });
  }
  if (typeof wanted !== "string" || !isUuid(wanted)) throw new HttpError(400, "bad_request", "user_id must be a UUID.");
  await rateLimit(`profile:${me}`, 1, config.profilePerMinute(), 60);
  const { data, error } = await admin().from("profiles")
    .select("user_id, display_name, username, school, about_emoji, about_text, hide_from_search").eq("user_id", wanted).maybeSingle();
  if (error) throw new HttpError(500, "internal");
  if (!data) throw new HttpError(404, "not_found", "No such profile.");
  return json({
    profile: {
      user_id: data.user_id,
      display_name: data.display_name,
      username: data.hide_from_search ? null : data.username,
      school: data.hide_from_search ? null : data.school,
      about_emoji: data.hide_from_search ? null : data.about_emoji,
      about_text: data.hide_from_search ? null : data.about_text,
    },
  });
}));
