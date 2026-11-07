// POST waitlist-join { email, list }: someone asked limemessenger.com to tell them when lime is ready (list "launch") or on Android (list "android"). LIME-284c2.
//
// Double opt-in: the address is stored UNCONFIRMED and a confirm email goes out (from send.limemessenger.com, through Resend). The reply is the same whether the address was
// new, waiting or already confirmed, so this cannot be used to check who is on the list. Rate limits count keyed hashes only (the caller, and the address): neither is stored.
// **No session** (a visitor has none). A browser's plain form post gets a redirect to a page on limemessenger.com; a script (`Accept: application/json`) gets JSON.
// Logs nothing identifying.

import { admin, rateLimit } from "../_shared/db.ts";
import { HttpError } from "../_shared/http.ts";
import { normaliseEmail } from "../_shared/auth.ts";
import { ipBucket } from "../_shared/ipbucket.ts";
import { sendNotice } from "../_shared/notify.ts";
import { confirmNotice, functionsUrl, hashedBucket, isToken, LISTS, type List, newToken, readFields, redirect, reply, waitlistServe } from "../_shared/waitlist.ts";

Deno.serve(waitlistServe(async (req, json) => {
  const fields = await readFields(req);
  const list = (fields.list ?? "launch") as List;
  if (!(LISTS as readonly string[]).includes(list)) throw new HttpError(400, "bad_request", "Unknown list.");
  // The caller first (a school shares one address, so the cap is generous), then the address (a few emails an hour to one person).
  await rateLimit(await ipBucket(req, "waitlist"), 1, 30, 600);
  const email = normaliseEmail(fields.email);
  await rateLimit(await hashedBucket("waitlist:email", `${list}|${email}`), 1, 3, 3600);

  const db = admin();
  const { data: row, error } = await db.from("waitlist").select("token, confirmed_at").eq("email", email).eq("list", list).maybeSingle();
  if (error) throw new HttpError(500, "internal");
  let token: string | null = null;
  if (!row) {
    token = newToken();
    const { error: insertError } = await db.from("waitlist").insert({ email, list, token });
    if (insertError && insertError.code !== "23505") throw new HttpError(500, "internal");   // a race with the same address: the other request sends the email
    if (insertError) token = null;
  } else if (row.confirmed_at === null && isToken(row.token)) {
    token = row.token;   // still waiting: send the same link again
  }
  if (token) {
    const sent = await sendNotice(email, confirmNotice(`${functionsUrl()}/waitlist-confirm?t=${token}`, list));
    if (!sent) console.error("waitlist: confirm email not sent");
  }
  return json ? reply(req, { ok: true }) : redirect(req, "/check-email/");
}));
