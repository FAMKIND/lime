// POST signup-set-password { password }: the last step of creating an account. Only a session that
// proved its email by code, for an account with no profile yet, may call it; it then has both
// steps (the code, and the password it just chose). It returns a fresh, verified session.

import { admin, requireSession } from "../_shared/db.ts";
import { MIN_PASSWORD_LENGTH, verifiedSessionFor } from "../_shared/auth.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const session = await requireSession(req);
  const body = await readJson(req);
  const password = typeof body.password === "string" ? body.password : "";
  if (password.length < MIN_PASSWORD_LENGTH || password.length > 256) {
    throw new HttpError(400, "weak_password", `Use at least ${MIN_PASSWORD_LENGTH} characters.`);
  }
  const db = admin();
  const { data: proof } = await db.from("auth_proofs").select("code_ok").eq("session_id", session.sessionId).maybeSingle();
  if (!proof?.code_ok) throw new HttpError(403, "code_first", "Verify your email with the code first.");
  // Only a brand new account (one that has no profile yet) chooses its password here; a forgotten
  // password goes through reset-verify.
  const { data: profile } = await db.from("profiles").select("user_id").eq("user_id", session.userId).maybeSingle();
  if (profile) throw new HttpError(409, "account_set_up", "This account is already set up.");

  const { error } = await db.auth.admin.updateUserById(session.userId, { password });
  if (error) throw new HttpError(400, "weak_password", "That password was not accepted. Try a longer one.");
  if (!session.email) throw new HttpError(403, "forbidden");
  // The password change ended this session: hand back a fresh one that has passed both steps.
  return json(await verifiedSessionFor(session.email, password, session.userId));
}));
