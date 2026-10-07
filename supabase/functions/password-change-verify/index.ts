// POST password-change-verify { code, new_password }: step two. The emailed code (5 wrong tries, then
// locked) and the new password. Changing a password ends the account's other sessions, so a fresh
// session that has passed both steps is returned, as for a password reset.
import { admin, requireUser } from "../_shared/db.ts";
import { CODE_PATTERN, authCall, MAX_CODE_ATTEMPTS, MIN_PASSWORD_LENGTH, verifiedSessionFor } from "../_shared/auth.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const body = await readJson(req);
  const password = typeof body.new_password === "string" ? body.new_password : "";
  if (typeof body.code !== "string" || !CODE_PATTERN.test(body.code)) throw new HttpError(400, "bad_request", "The code is 6 to 8 digits.");
  if (password.length < MIN_PASSWORD_LENGTH || password.length > 256) {
    throw new HttpError(400, "weak_password", `Use at least ${MIN_PASSWORD_LENGTH} characters.`);
  }
  const db = admin();
  const { data: owner } = await db.auth.admin.getUserById(userId);
  const email = owner?.user?.email;
  if (!email) throw new HttpError(500, "internal");

  const { data: attempts, error } = await db.rpc("take_code_attempt", { p_key: `pwchange:${userId}`, p_max: MAX_CODE_ATTEMPTS });
  if (error) throw new HttpError(500, "internal");
  if (attempts > MAX_CODE_ATTEMPTS) throw new HttpError(429, "locked", "Too many wrong codes. Ask for a new one.");
  const checked = await authCall("/verify", { type: "email", email, token: body.code });
  if (checked.status !== 200) {
    throw new HttpError(400, "bad_code", `That code is not right. ${MAX_CODE_ATTEMPTS - attempts} tries left.`);
  }
  const { error: updateError } = await db.auth.admin.updateUserById(userId, { password });
  if (updateError) throw new HttpError(400, "weak_password", "That password was not accepted. Try a longer one.");
  return json(await verifiedSessionFor(email, password, userId));
}));
