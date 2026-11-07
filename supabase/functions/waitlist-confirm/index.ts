// GET waitlist-confirm?t=<token>: the link in the confirm email. Marks the address confirmed and sends the visitor to limemessenger.com/confirmed/ (LIME-284c2).
// An unknown or expired token goes to the "try again" page. The token is the only proof; no session. Logs nothing identifying.

import { admin, rateLimit } from "../_shared/db.ts";
import { HttpError } from "../_shared/http.ts";
import { ipBucket } from "../_shared/ipbucket.ts";
import { isToken, readFields, redirect, waitlistServe } from "../_shared/waitlist.ts";

Deno.serve(waitlistServe(async (req) => {
  const fields = await readFields(req);
  await rateLimit(await ipBucket(req, "waitlist-token"), 1, 60, 600);
  const token = fields.t;
  if (!isToken(token)) return redirect(req, "/try-again/");
  const db = admin();
  const { data: row, error } = await db.from("waitlist").select("token, confirmed_at").eq("token", token).maybeSingle();
  if (error) throw new HttpError(500, "internal");
  if (!row) return redirect(req, "/try-again/");
  if (row.confirmed_at === null) {
    const { error: updateError } = await db.from("waitlist").update({ confirmed_at: new Date().toISOString() }).eq("token", token);
    if (updateError) throw new HttpError(500, "internal");
  }
  return redirect(req, `/confirmed/?t=${token}`);
}));
