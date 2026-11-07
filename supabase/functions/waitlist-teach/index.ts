// POST waitlist-teach { t, v }: the optional "I teach in…" tap on the confirmed page (LIME-284c2). `v` is one of k12, higher_ed, studio_community, other; it can be changed by
// tapping again, and is never required. Only a CONFIRMED row takes it. The token is the only proof; no session. Logs nothing identifying.

import { admin, rateLimit } from "../_shared/db.ts";
import { HttpError } from "../_shared/http.ts";
import { ipBucket } from "../_shared/ipbucket.ts";
import { isToken, readFields, redirect, reply, TEACHES, waitlistServe } from "../_shared/waitlist.ts";

Deno.serve(waitlistServe(async (req, json) => {
  const fields = await readFields(req);
  await rateLimit(await ipBucket(req, "waitlist-token"), 1, 60, 600);
  const token = fields.t, value = fields.v;
  if (!isToken(token) || !(TEACHES as readonly string[]).includes(value)) throw new HttpError(400, "bad_request", "That did not look right.");
  const { data, error } = await admin().from("waitlist").update({ teaches: value }).eq("token", token).not("confirmed_at", "is", null).select("email");
  if (error) throw new HttpError(500, "internal");
  if (!data || data.length === 0) throw new HttpError(404, "not_found", "That link is no longer valid.");
  return json ? reply(req, { ok: true }) : redirect(req, `/confirmed/?t=${token}`);
}));
