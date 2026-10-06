// POST users-lookup { email }: the user id for an EXACT email match (case-insensitive), or 404.
// Authenticated and rate-limited. It never lists anyone and returns no profile data.

import { admin, config, rateLimit, requireUser } from "../_shared/db.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const body = await readJson(req);
  const email = typeof body.email === "string" ? body.email.trim() : "";
  if (email.length < 3 || email.length > 254 || !email.includes("@")) {
    throw new HttpError(400, "bad_request", "email must be a full email address.");
  }
  await rateLimit(`lookup:${userId}`, 1, config.lookupPerMinute(), 60);

  const { data, error } = await admin().rpc("lookup_user_id_by_email", { p_email: email });
  if (error) throw new HttpError(500, "internal");
  if (!data) throw new HttpError(404, "not_found", "No account has that email.");
  return json({ user_id: data });
}));
