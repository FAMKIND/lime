// GET or POST waitlist-unsubscribe?t=<token>: one click, and the row is gone (LIME-284c2). A link in an email opens it (GET: the visitor lands on limemessenger.com/left/);
// a mail app's one-click "unsubscribe" posts to it (POST: 200). The token is the only proof; no session. Logs nothing identifying.

import { admin, rateLimit } from "../_shared/db.ts";
import { HttpError } from "../_shared/http.ts";
import { ipBucket } from "../_shared/ipbucket.ts";
import { isToken, readFields, redirect, reply, waitlistServe } from "../_shared/waitlist.ts";

Deno.serve(waitlistServe(async (req, json) => {
  const url = new URL(req.url);
  const fields = req.method === "GET" ? Object.fromEntries(url.searchParams) : { ...Object.fromEntries(url.searchParams), ...(await readFields(req)) };
  await rateLimit(await ipBucket(req, "waitlist-token"), 1, 60, 600);
  const token = fields.t;
  if (!isToken(token)) throw new HttpError(400, "bad_request", "That link is not valid.");
  const { error } = await admin().from("waitlist").delete().eq("token", token);
  if (error) throw new HttpError(500, "internal");
  // The same answer whether a row was there or not.
  return req.method === "POST" || json ? reply(req, { ok: true }) : redirect(req, "/left/");
}));
