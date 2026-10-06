// POST code-resend: a new emailed code for a sign-in, at most one every 30 seconds. A new code
// starts the count of wrong tries again.

import { admin, accountConfig, rateLimit, requireSession } from "../_shared/db.ts";
import { authCall, RESEND_AFTER_SECONDS, sha256Hex } from "../_shared/auth.ts";
import { handler, HttpError, json } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const session = await requireSession(req);
  if (!session.email) throw new HttpError(403, "forbidden");
  const db = admin();
  const { data: proof } = await db.from("auth_proofs").select("password_ok").eq("session_id", session.sessionId).maybeSingle();
  if (!proof?.password_ok) throw new HttpError(403, "password_first", "Enter your password first.");

  const key = `session:${session.sessionId}`;
  const { data: challenge } = await db.from("code_challenges").select("sent_at").eq("challenge_key", key).maybeSingle();
  if (challenge) {
    const waited = (Date.now() - new Date(challenge.sent_at).getTime()) / 1000;
    if (waited < RESEND_AFTER_SECONDS) {
      throw new HttpError(429, "too_soon", `Wait ${Math.ceil(RESEND_AFTER_SECONDS - waited)} seconds to ask for another code.`);
    }
  }
  await rateLimit(`email:${await sha256Hex(session.email)}`, 1, accountConfig.emailPerHour(), 3600);
  const sent = await authCall("/otp", { email: session.email, create_user: false });
  if (sent.status !== 200) throw new HttpError(502, "email_failed", "We could not send the code. Try again in a moment.");
  await db.rpc("start_code_challenge", { p_key: key, p_kind: "signin" });
  return json({ ok: true });
}));
