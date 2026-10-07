// POST password-change-start { current_password }: step one of changing the password from Settings.
// The caller has a verified session. The FUNCTION checks the current password with Supabase Auth,
// then emails a code (the same second proof as signing in). Nothing changes yet, and the new
// password is never sent here: password-change-verify takes it together with the code.
import { admin, accountConfig, rateLimit, requireUser } from "../_shared/db.ts";
import { authCall, sendCode, sha256Hex } from "../_shared/auth.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const body = await readJson(req);
  const current = typeof body.current_password === "string" ? body.current_password : "";
  if (!current || current.length > 256) throw new HttpError(400, "bad_request", "Enter your current password.");
  await rateLimit(`pwcheck:${userId}`, 1, accountConfig.signInPerTenMinutes(), 600);

  const db = admin();
  const { data: owner } = await db.auth.admin.getUserById(userId);
  const email = owner?.user?.email;
  if (!email) throw new HttpError(500, "internal");
  const checked = await authCall("/token", { email, password: current }, { query: "?grant_type=password" });
  if (checked.status !== 200) throw new HttpError(401, "invalid_credentials", "That is not your current password.");

  await db.rpc("start_code_challenge", { p_key: `pwchange:${userId}`, p_kind: "password-change" });
  await rateLimit(`email:${await sha256Hex(email)}`, 1, accountConfig.emailPerHour(), 3600);
  await sendCode(email, false);
  return json({ ok: true });
}));
