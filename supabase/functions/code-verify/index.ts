// POST code-verify { code }: step two of signing in. The FUNCTION checks the emailed code with
// Supabase Auth and counts wrong tries (5, then the code is locked). On success the session has
// passed both steps and becomes verified.

import { admin, requireSession } from "../_shared/db.ts";
import { CODE_PATTERN, authCall, MAX_CODE_ATTEMPTS } from "../_shared/auth.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const session = await requireSession(req);
  const body = await readJson(req);
  if (typeof body.code !== "string" || !CODE_PATTERN.test(body.code)) {
    throw new HttpError(400, "bad_request", "The code is 6 to 8 digits.");
  }
  const db = admin();
  const { data: proof } = await db.from("auth_proofs").select("password_ok, code_ok").eq("session_id", session.sessionId).maybeSingle();
  if (!proof?.password_ok) throw new HttpError(403, "password_first", "Enter your password first.");
  if (proof.code_ok) return json({ verified: true });
  if (!session.email) throw new HttpError(403, "forbidden");

  const { data: attempts, error } = await db.rpc("take_code_attempt", { p_key: `session:${session.sessionId}`, p_max: MAX_CODE_ATTEMPTS });
  if (error) throw new HttpError(500, "internal");
  if (attempts > MAX_CODE_ATTEMPTS) {
    throw new HttpError(429, "locked", "Too many wrong codes. Sign in again to get a new one.");
  }
  const checked = await authCall("/verify", { type: "email", email: session.email, token: body.code });
  if (checked.status !== 200) {
    throw new HttpError(400, "bad_code", `That code is not right. ${MAX_CODE_ATTEMPTS - attempts} tries left.`);
  }
  const { error: updateError } = await db.from("auth_proofs")
    .update({ code_ok: true, verified_at: new Date().toISOString() }).eq("session_id", session.sessionId);
  if (updateError) throw new HttpError(500, "internal");
  return json({ verified: true });
}));
