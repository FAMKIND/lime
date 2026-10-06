// POST signup-start { email }: step one of creating an account: email a 6-digit code to the
// address (which proves it is theirs). An address that already has an account is refused (the
// client signs in instead).

import { admin, accountConfig, rateLimit } from "../_shared/db.ts";
import { authCall, clientIp, maskEmail, normaliseEmail, sha256Hex } from "../_shared/auth.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const body = await readJson(req);
  const email = normaliseEmail(body.email);
  await rateLimit(`signup:ip:${clientIp(req)}`, 1, accountConfig.identifyPerMinute(), 60);
  const db = admin();
  const { data: existing } = await db.rpc("lookup_user_id_by_email", { p_email: email });
  if (existing) throw new HttpError(409, "account_exists", "That email already has an account. Sign in instead.");

  const hash = await sha256Hex(email);
  await rateLimit(`email:${hash}`, 1, accountConfig.emailPerHour(), 3600);
  const sent = await authCall("/otp", { email, create_user: true });
  if (sent.status !== 200) throw new HttpError(502, "email_failed", "We could not send the code. Try again in a moment.");
  await db.rpc("start_code_challenge", { p_key: `email:${hash}`, p_kind: "signup" });
  return json({ ok: true, masked_email: maskEmail(email) });
}));
