// POST profile-set { display_name, username?, school?, hide_from_search? }: creates or updates the
// signed-in user's own profile. The directory fields only (api-v2.md section 2). A verified
// session is required. Usernames follow the web app's rules and are unique ignoring case.

import { admin, requireUser } from "../_shared/db.ts";
import { usernameError } from "../_shared/auth.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const body = await readJson(req);
  const displayName = typeof body.display_name === "string" ? body.display_name.trim() : "";
  if (displayName.length < 1 || displayName.length > 60) throw new HttpError(400, "bad_request", "Your name is 1 to 60 characters.");

  let username: string | null = null;
  if (typeof body.username === "string" && body.username.trim() !== "") {
    username = body.username.trim().replace(/^@/, "");
    const problem = usernameError(username);
    if (problem) throw new HttpError(400, "bad_username", problem);
  }
  let school: string | null = null;
  if (typeof body.school === "string" && body.school.trim() !== "") {
    school = body.school.trim();
    if (school.length > 120) throw new HttpError(400, "bad_request", "The school name is too long.");
  }

  const row: Record<string, unknown> = {
    user_id: userId, display_name: displayName, username, school, updated_at: new Date().toISOString(),
  };
  if (typeof body.hide_from_search === "boolean") row.hide_from_search = body.hide_from_search;
  const { data, error } = await admin().from("profiles").upsert(row, { onConflict: "user_id" })
    .select("user_id, display_name, username, school, hide_from_search").single();
  if (error) {
    if (error.code === "23505") throw new HttpError(409, "username_taken", "That username is taken. Try another.");
    throw new HttpError(500, "internal");
  }
  return json(data);
}));
