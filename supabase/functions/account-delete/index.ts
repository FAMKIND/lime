// POST account-delete { password, code } -> { token }: step two of deleting the account (LIME-113, App Store rule 5.1.1(v)); it only MARKS it as "deleting"
// (LIME-113c) and returns a one-time token for account-delete-confirm. Needs a verified session, the password
// (checked with Supabase Auth) and the emailed code from account-delete-start (5 wrong tries, then locked).
//
// Deleted: the auth user and its sessions, the profile and its Everyone objects (photo, links, background, background video), contacts-only and
// jam blobs, attachment chunks, devices and every key, delivery access, mailbox items to and from the account, jam pages, reports FILED by it, codes
// and rate-limit counters. Kept: reports ABOUT it (sealed; their 180 days apply), a log row (a hash of the user id and the time), and the USERNAME,
// held for 30 days. What others already have on their phones is out of the server's reach (end-to-end encryption).
//
// Nothing here logs the user id, the email or the password.
import { admin, accountConfig, rateLimit, requireUser } from "../_shared/db.ts";
import { CODE_PATTERN, authCall, MAX_CODE_ATTEMPTS, sha256Hex } from "../_shared/auth.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  await rateLimit(`account-delete:${userId}`, 1, accountConfig.setPasswordPer10Min(), 600);
  const body = await readJson(req);
  const password = typeof body.password === "string" ? body.password : "";
  if (!password || password.length > 256) throw new HttpError(400, "bad_request", "Enter your password.");
  if (typeof body.code !== "string" || !CODE_PATTERN.test(body.code)) throw new HttpError(400, "bad_request", "The code is 6 to 8 digits.");
  const db = admin();
  const { data: owner } = await db.auth.admin.getUserById(userId);
  const email = owner?.user?.email;
  if (!email) throw new HttpError(500, "internal");

  const { data: attempts, error } = await db.rpc("take_code_attempt", { p_key: `account-delete:${userId}`, p_max: MAX_CODE_ATTEMPTS });
  if (error) throw new HttpError(500, "internal");
  if (attempts > MAX_CODE_ATTEMPTS) throw new HttpError(429, "locked", "Too many wrong codes. Ask for a new one.");
  const passwordOk = await authCall("/token", { email, password }, { query: "?grant_type=password" });
  if (passwordOk.status !== 200) throw new HttpError(401, "invalid_credentials", "That is not your password.");
  const checked = await authCall("/verify", { type: "email", email, token: body.code });
  if (checked.status !== 200) throw new HttpError(400, "bad_code", `That code is not right. ${MAX_CODE_ATTEMPTS - attempts} tries left.`);

  // The checks passed: the account is marked "deleting" (sign-in and every call but the confirm are refused) and the phone gets a one-time token.
  // Nothing is deleted yet; the phone sends its quiet notices first (LIME-113c).
  const token = Array.from(crypto.getRandomValues(new Uint8Array(24)), (b) => b.toString(16).padStart(2, "0")).join("");
  const { error: markError } = await db.from("account_suspensions").upsert({ user_id: userId, reason: "deleting", created_by: null });
  if (markError) throw new HttpError(500, "internal");
  const { error: tokenError } = await db.from("account_deletions").upsert({ user_id: userId, token_hash: await sha256Hex(token), started_at: new Date().toISOString(), notices_sent_at: null });
  if (tokenError) throw new HttpError(500, "internal");
  return json({ token });
}));
