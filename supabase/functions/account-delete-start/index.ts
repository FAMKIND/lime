// POST account-delete-start { password } -> { ok }: step one of deleting the account from Settings (LIME-113). Like changing the password: the caller has a
// verified session, the FUNCTION checks the password with Supabase Auth, then emails a code. Nothing is deleted yet.
import { admin, accountConfig, rateLimit, requireUser } from "../_shared/db.ts";
import { authCall, sendCode, sha256Hex } from "../_shared/auth.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const body = await readJson(req);
  const password = typeof body.password === "string" ? body.password : "";
  if (!password || password.length > 256) throw new HttpError(400, "bad_request", "Enter your password.");
  await rateLimit(`pwcheck:${userId}`, 1, accountConfig.signInPerTenMinutes(), 600);

  const db = admin();
  const { data: owner } = await db.auth.admin.getUserById(userId);
  const email = owner?.user?.email;
  if (!email) throw new HttpError(500, "internal");
  const checked = await authCall("/token", { email, password }, { query: "?grant_type=password" });
  if (checked.status !== 200) throw new HttpError(401, "invalid_credentials", "That is not your password.");

  await db.rpc("start_code_challenge", { p_key: `account-delete:${userId}`, p_kind: "account-delete" });
  await rateLimit(`email:${await sha256Hex(email)}`, 1, accountConfig.emailPerHour(), 3600);
  await sendCode(email, false);
  return json({ ok: true });
}));
