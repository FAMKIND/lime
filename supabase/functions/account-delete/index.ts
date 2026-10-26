// POST account-delete { password, code } -> { ok }: deletes the account (LIME-113, App Store rule 5.1.1(v)). Needs a verified session, the password
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
import { chunkPath, listChunks } from "../_shared/attachments.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { AVATAR_BUCKET, BLOB_BUCKET, removeObject } from "../_shared/storage.ts";

const AVATAR_OBJECTS = (u: string) => [`${u}.jpg`, `${u}-links.json`, `${u}-background.jpg`, `${u}-background.mp4`];

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

  // 1. Storage first (the rows that name the objects go with the auth user afterwards). Safe to repeat.
  for (const name of AVATAR_OBJECTS(userId)) await removeObject(AVATAR_BUCKET, name);
  for (let page = 0; page < 20; page++) {
    const { data: blobs } = await db.from("blobs").select("id").eq("owner", userId).limit(500);
    if (!blobs || blobs.length === 0) break;
    for (const row of blobs) {
      await removeObject(BLOB_BUCKET, row.id);
      await db.from("blobs").delete().eq("id", row.id);
    }
  }
  const { data: attachments } = await db.from("attachments").select("id").eq("owner", userId).limit(5000);
  for (const row of attachments ?? []) {
    for (const n of (await listChunks(row.id)).keys()) await removeObject(BLOB_BUCKET, chunkPath(row.id, n));
  }
  // 2. The username hold, the log row, what does not cascade.
  const { error: rowsError } = await db.rpc("delete_account_rows", { p_user: userId, p_hash: await sha256Hex(userId) });
  if (rowsError) throw new HttpError(500, "internal");
  // 3. The account itself: its sessions end and its rows cascade.
  const { error: deleteError } = await db.auth.admin.deleteUser(userId);
  if (deleteError) throw new HttpError(500, "internal");
  return json({ ok: true });
}));
