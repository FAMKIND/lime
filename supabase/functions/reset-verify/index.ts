// POST reset-verify { identifier, code, new_password }: the code (5 wrong tries, then locked) and a
// new password in one step. Having proved the email by code and chosen the password, the new
// session has both steps and is verified.

import { admin } from "../_shared/db.ts";
import { authCall, MAX_CODE_ATTEMPTS, MIN_PASSWORD_LENGTH, resolveEmail, sha256Hex, verifiedSessionFor } from "../_shared/auth.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const body = await readJson(req);
  const identifier = typeof body.identifier === "string" ? body.identifier : typeof body.email === "string" ? body.email : "";
  const email = identifier.trim() ? await resolveEmail(identifier) : null;
  if (!email) throw new HttpError(400, "bad_code", "That code is not right.");
  const password = typeof body.new_password === "string" ? body.new_password : "";
  if (typeof body.code !== "string" || !/^\d{6}$/.test(body.code)) throw new HttpError(400, "bad_request", "The code is 6 digits.");
  if (password.length < MIN_PASSWORD_LENGTH || password.length > 256) {
    throw new HttpError(400, "weak_password", `Use at least ${MIN_PASSWORD_LENGTH} characters.`);
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
  const { error: updateError } = await db.auth.admin.updateUserById(session.user.id, { password });
  if (updateError) throw new HttpError(400, "weak_password", "That password was not accepted. Try a longer one.");
  // The password change ended the session the code gave: return a fresh one that has both steps.
  return json(await verifiedSessionFor(email, password, session.user.id));
}));
