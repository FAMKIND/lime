// POST profile-get: the signed-in user's own profile, or { profile: null } for a new account.

import { admin, requireUser } from "../_shared/db.ts";
import { handler, HttpError, json } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const { data, error } = await admin().from("profiles")
    .select("user_id, display_name, username, school, hide_from_search").eq("user_id", userId).maybeSingle();
  if (error) throw new HttpError(500, "internal");
  return json({ profile: data ?? null });
}));
