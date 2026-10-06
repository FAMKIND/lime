// POST signup-verify { email, code }: checks the emailed code (5 wrong tries, then locked) and
// returns the new session. The session has proven the email only: it must still set a password
// (signup-set-password) before it can do anything.

import { admin, sessionIdOf } from "../_shared/db.ts";
import { CODE_PATTERN, authCall, MAX_CODE_ATTEMPTS, normaliseEmail, sha256Hex } from "../_shared/auth.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const body = await readJson(req);
  const email = normaliseEmail(body.email);
  if (typeof body.code !== "string" || !CODE_PATTERN.test(body.code)) {
    throw new HttpError(400, "bad_request", "The code is 6 to 8 digits.");
  }
  const db = admin();
  const key = `email:${await sha256Hex(email)}`;
  const { data: attempts, error } = await db.rpc("take_code_attempt", { p_key: key, p_max: MAX_CODE_ATTEMPTS });
  if (error) throw new HttpError(500, "internal");
  if (attempts > MAX_CODE_ATTEMPTS) throw new HttpError(429, "locked", "Too many wrong codes. Ask for a new one.");

  const checked = await authCall("/verify", { type: "email", email, token: body.code });
  const session = checked.body;
  if (checked.status !== 200 || !session?.access_token || !session?.user?.id) {
    throw new HttpError(400, "bad_code", `That code is not right. ${MAX_CODE_ATTEMPTS - attempts} tries left.`);
  }
  const sessionId = sessionIdOf(session.access_token);
  if (!sessionId) throw new HttpError(500, "internal");
  const { error: proofError } = await db.from("auth_proofs").upsert({
    session_id: sessionId, user_id: session.user.id, password_ok: false, code_ok: true,
  });
  if (proofError) throw new HttpError(500, "internal");
  return json({
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_in: session.expires_in,
    expires_at: session.expires_at,
    user_id: session.user.id,
  });
}));
