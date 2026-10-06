// POST reset-start { identifier }: "Forgot password?": email a 6-digit code to the account's address.
// The identifier is an email or a username (resolved here). It always answers the same way, so it
// does not reveal whether the account exists (except when sending an email to an existing account fails).

import { admin, accountConfig, rateLimit } from "../_shared/db.ts";
import { clientIp, resolveEmail, sendCode, sha256Hex } from "../_shared/auth.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const body = await readJson(req);
  const identifier = typeof body.identifier === "string" ? body.identifier : typeof body.email === "string" ? body.email : "";
  if (!identifier.trim() || identifier.length > 254) throw new HttpError(400, "bad_request", "Enter your email or username.");
  await rateLimit(`reset:ip:${clientIp(req)}`, 1, accountConfig.identifyPerMinute(), 60);
  const email = await resolveEmail(identifier);
  const db = admin();
  const { data: state } = email ? await db.rpc("email_account_state", { p_email: email }) : { data: "none" };
  if (email && state === "confirmed") {
    const hash = await sha256Hex(email);
    await rateLimit(`email:${hash}`, 1, accountConfig.emailPerHour(), 3600);
    // A send that fails or is rate-limited is reported (never "we sent a code" when none was sent). It
    // is the one case that tells a caller an account exists, and only when the email could not go out.
    await sendCode(email, false);
    await db.rpc("start_code_challenge", { p_key: `email:${hash}`, p_kind: "reset" });
  }
  return json({ ok: true });
}));
