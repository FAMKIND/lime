// GET or POST waitlist-android?t=<token>: "Tell me when it's on Android", the link in the launch email (LIME-287a). Moves the confirmed row to the Android list and keeps it (its token stays
// the same, so "delete it now" still works); the Android email goes out later (waitlist-send, kind "android"). The visitor lands on limemessenger.com/android-list/. An address already on the
// Android list just loses its launch row. The token is the only proof; no session. Logs nothing identifying.

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
  const db = admin();
  const { data: row, error } = await db.from("waitlist").select("email, list, confirmed_at").eq("token", token).maybeSingle();
  if (error) throw new HttpError(500, "internal");
  if (!row || row.confirmed_at === null) throw new HttpError(404, "not_found", "That link is no longer valid.");
  if (row.list === "launch") {
    const { data: already } = await db.from("waitlist").select("token").eq("email", row.email).eq("list", "android").maybeSingle();
    if (already) {
      await db.from("waitlist").delete().eq("token", token);
    } else {
      const { error: moveError } = await db.from("waitlist").update({ list: "android", sent_at: null }).eq("token", token);
      if (moveError) throw new HttpError(500, "internal");
    }
  }
  return req.method === "POST" || json ? reply(req, { ok: true }) : redirect(req, "/android-list/");
}));
