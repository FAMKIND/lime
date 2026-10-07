// POST users-find { query }: the person with that EXACT username or EXACT email (case-insensitive),
// as public profile fields only, or 404. Authenticated and rate-limited. It never lists or
// partially matches, never returns an email or phone, and finds nobody who hid themselves from
// search (they get the same 404 as a person who does not exist).

import { admin, config, rateLimit, requireUser } from "../_shared/db.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { usernameError } from "../_shared/auth.ts";

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  const body = await readJson(req);
  const query = typeof body.query === "string" ? body.query.trim() : "";
  if (query.length < 3 || query.length > 254) {
    throw new HttpError(400, "bad_request", "Enter a username or a full email address.");
  }
  await rateLimit(`lookup:${me}`, 1, config.lookupPerMinute(), 60);

  const notFound = new HttpError(404, "not_found", "No teacher found with that username or email.");
  let userId: string | null = null;
  if (query.includes("@") && !query.startsWith("@")) {
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(query)) throw new HttpError(400, "bad_request", "Enter a full email address.");
    const { data, error } = await admin().rpc("lookup_user_id_by_email", { p_email: query });
    if (error) throw new HttpError(500, "internal");
    userId = data ?? null;
  } else {
    const username = query.replace(/^@/, "");
    if (usernameError(username)) throw notFound;
    const { data, error } = await admin().rpc("resolve_username", { p_username: username });
    if (error) throw new HttpError(500, "internal");
    userId = Array.isArray(data) ? data[0]?.user_id ?? null : null;
  }
  if (!userId) throw notFound;

  const { data: profile, error } = await admin().from("profiles")
    .select("user_id, display_name, username, school, about_emoji, about_text, hide_from_search").eq("user_id", userId).maybeSingle();
  if (error) throw new HttpError(500, "internal");
  if (!profile || (profile.hide_from_search && userId !== me)) throw notFound;
  return json({
    user_id: profile.user_id,
    display_name: profile.display_name,
    username: profile.username,
    school: profile.school,
    about_emoji: profile.about_emoji,
    about_text: profile.about_text,
    is_self: userId === me,
  });
}));
