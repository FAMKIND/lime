// A smoke test of LIME-113/113c against STAGING (run by ./supabase/smoke-deletion-staging.sh). THROWAWAY users only (never a real account). The emailed
// code cannot be read on staging, so the "mark" is made through the service role; everything after it is the real path: a refused account, the
// confirm (notices, then delete) with its token, the sweep for an unconfirmed one, and the log and the username hold.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { admin, ANON_KEY, API_URL, call, newUser, type TestUser } from "./helpers.ts";

async function hash(text: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return Array.from(digest, (x) => x.toString(16).padStart(2, "0")).join("");
}
async function rows(table: string, column: string, value: string): Promise<number> {
  const { count } = await admin.from(table).select("*", { count: "exact", head: true }).eq(column, value);
  return count ?? 0;
}
async function mark(user: TestUser): Promise<string> {
  const token = "t" + crypto.randomUUID();
  await admin.from("account_suspensions").upsert({ user_id: user.id, reason: "deleting" });
  await admin.from("account_deletions").upsert({ user_id: user.id, token_hash: await hash(token), started_at: new Date().toISOString(), notices_sent_at: null });
  return token;
}

const gone = await newUser();      // confirmed by its token
const swept = await newUser();     // finished by the sweep
const bystander = await newUser(); // never touched
const made: TestUser[] = [gone, swept, bystander];
try {
  const username = "smoke" + crypto.randomUUID().slice(0, 7);
  assertEquals((await call("profile-set", gone.token, { display_name: "Gone", username })).status, 200);
  for (const u of [swept, bystander]) assertEquals((await call("profile-set", u.token, { display_name: "X" })).status, 200);

  // The functions answer, and refuse what they should.
  assertEquals((await call("account-delete-start", null, { password: "x" })).status, 401);
  assertEquals((await call("account-delete-start", gone.token, { password: "not the password" })).status, 401);
  assertEquals((await call("account-delete", gone.token, { password: "x", code: "000000" })).status, 429, "no code was ever sent: refused as locked");
  assertEquals(await rows("profiles", "user_id", gone.id), 1, "refusals delete nothing");
  assertEquals(await rows("account_suspensions", "user_id", gone.id), 0, "and mark nothing");

  // Marked: refused everywhere, except the confirm.
  const token = await mark(gone);
  const refused = await call("profile-get", gone.token, {});
  assertEquals([refused.status, refused.body.error], [403, "suspended"]);
  assertEquals((await call("account-delete-confirm", gone.token, { token: "wrong", step: "delete" })).status, 403);
  assertEquals((await call("account-delete-confirm", bystander.token, { token, step: "delete" })).status, 403);
  assertEquals((await call("account-delete-confirm", gone.token, { token, step: "notices" })).status, 200);
  assertEquals(await rows("profiles", "user_id", gone.id), 1, "the notices step deletes nothing");
  assertEquals((await call("account-delete-confirm", gone.token, { token, step: "delete" })).status, 200);
  assertEquals(await rows("profiles", "user_id", gone.id), 0, "deleted");
  assertEquals((await call("profile-get", gone.token, {})).status, 401, "the session is gone");
  assertEquals(await rows("profiles", "user_id", bystander.id), 1, "a bystander is untouched");
  assertEquals(await rows("deleted_accounts", "id_hash", await hash(gone.id)), 1, "the log row");
  const taken = await call("profile-set", bystander.token, { display_name: "X", username });
  assertEquals([taken.status, taken.body.error], [409, "username_taken"], "the username is held");

  // The sweep finishes an unconfirmed one (24 hours after the start).
  await mark(swept);
  await admin.from("account_deletions").update({ started_at: new Date(Date.now() - 25 * 3600_000).toISOString() }).eq("user_id", swept.id);
  const { data: target } = await admin.from("sweep_target").select("secret").eq("id", 1).maybeSingle();
  assert(target, "staging has a sweep secret");
  const res = await fetch(API_URL + "/functions/v1/blob-sweep", { method: "POST", headers: { "x-sweep-secret": target!.secret, apikey: ANON_KEY } });
  await res.body?.cancel();
  assertEquals(res.status, 200);
  assertEquals(await rows("profiles", "user_id", swept.id), 0, "the sweep finished it");
  assertEquals(await rows("profiles", "user_id", bystander.id), 1);
  console.log("staging deletion smoke test passed: refusals, mark, confirm (wrong token, notices, delete), log, username hold, sweep");
} finally {
  for (const u of made) {
    await admin.auth.admin.deleteUser(u.id).catch(() => {});
    await admin.from("deleted_accounts").delete().eq("id_hash", await hash(u.id));
  }
  await admin.from("held_usernames").delete().like("username", "smoke%");
}
