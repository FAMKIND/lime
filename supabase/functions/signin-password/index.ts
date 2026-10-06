// POST signin-password { identifier, password }: step one of signing in. The FUNCTION checks the
// password with Supabase Auth (so a username never has to be turned into an email on the phone),
// records "password ok" for the new session, and emails a 6-digit code. The session is returned,
// but it can do nothing until the code is verified (code-verify): see _shared/db.ts requireUser.

import { admin, accountConfig, rateLimit, sessionIdOf } from "../_shared/db.ts";
import { authCall, clientIp, maskEmail, normaliseEmail, sendCode, sha256Hex, usernameError } from "../_shared/auth.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const body = await readJson(req);
  const identifier = typeof body.identifier === "string" ? body.identifier.trim() : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (!identifier || identifier.length > 254 || !password || password.length > 256) {
    throw new HttpError(400, "bad_request", "Enter your email or username and your password.");
  }
  await rateLimit(`signin:ip:${clientIp(req)}`, 1, accountConfig.signInPerTenMinutes(), 600);
  await rateLimit(`signin:id:${await sha256Hex(identifier.toLowerCase())}`, 1, accountConfig.signInPerTenMinutes(), 600);

  // An email, or a username resolved on the server. Every failure looks the same: 401.
  const invalid = new HttpError(401, "invalid_credentials", "That email, username or password is not right.");
  let email: string;
  if (identifier.includes("@") && !identifier.startsWith("@")) {
    try {
      email = normaliseEmail(identifier);
    } catch {
      throw invalid;
    }
  } else {
    const username = identifier.replace(/^@/, "");
    if (usernameError(username)) throw invalid;
    const { data } = await admin().rpc("resolve_username", { p_username: username });
    const row = Array.isArray(data) ? data[0] : null;
    if (!row?.email) throw invalid;
    email = row.email;
  }

  const signedIn = await authCall("/token", { email, password }, { query: "?grant_type=password" });
  const session = signedIn.body;
  if (signedIn.status !== 200 || !session?.access_token || !session?.user?.id) throw invalid;
  const sessionId = sessionIdOf(session.access_token);
  if (!sessionId) throw new HttpError(500, "internal");

  const db = admin();
  const { error } = await db.from("auth_proofs").upsert({
    session_id: sessionId, user_id: session.user.id, password_ok: true, code_ok: false,
  });
  if (error) throw new HttpError(500, "internal");

  // The second step: the emailed code.
  await db.rpc("start_code_challenge", { p_key: `session:${sessionId}`, p_kind: "signin" });
  await rateLimit(`email:${await sha256Hex(email)}`, 1, accountConfig.emailPerHour(), 3600);
  await sendCode(email, false);

  return json({
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_in: session.expires_in,
    expires_at: session.expires_at,
    user_id: session.user.id,
    masked_email: maskEmail(email),
  });
}));
