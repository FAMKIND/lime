// LIME-98: the About line, name limits, hide-from-search, and changing the password from Settings.
// Against the LOCAL stack (the emailed codes come from its mail catcher): ./supabase/test.sh

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { admin, ANON_KEY, API_URL, call, clearMailbox, deleteUser, emailedCode, newUser, pause, sessionIdOf, type TestUser } from "./helpers.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };
const handle = () => `u${crypto.randomUUID().replaceAll("-", "").slice(0, 10)}`;

async function withUsers<T>(count: number, fn: (users: TestUser[]) => Promise<T>): Promise<T> {
  const users = await Promise.all(Array.from({ length: count }, newUser));
  try {
    return await fn(users);
  } finally {
    await Promise.all(users.map(deleteUser));
  }
}

Deno.test("About: an optional emoji and a few words, 140 characters in all, public like the name", opts, async () => {
  await withUsers(2, async ([me, other]) => {
    const username = handle();
    const saved = await call("profile-set", me.token, {
      display_name: "Ada Lovelace", username, school: "Bay School", about_emoji: "👋", about_text: "Happy to help",
    });
    assertEquals(saved.status, 200, JSON.stringify(saved.body));
    assertEquals([saved.body.about_emoji, saved.body.about_text], ["👋", "Happy to help"]);

    // Other people see it (through the same public rules as the name and school).
    assertEquals((await call("profile-get", other.token, { user_id: me.id })).body.profile.about_text, "Happy to help");
    const found = await call("users-find", other.token, { query: username });
    assertEquals([found.body.about_emoji, found.body.about_text], ["👋", "Happy to help"]);
    assertEquals((await call("profile-get", me.token, {})).body.profile.about_text, "Happy to help", "and you see your own");

    // 140 in all, emoji included; a family emoji counts as one.
    const family = "👨‍👩‍👧";
    assertEquals((await call("profile-set", me.token, { display_name: "Ada", about_emoji: family, about_text: "a".repeat(139) })).status, 200);
    assertEquals((await call("profile-set", me.token, { display_name: "Ada", about_emoji: "👋", about_text: "a".repeat(140) })).status, 400);
    assertEquals((await call("profile-set", me.token, { display_name: "Ada", about_text: "a".repeat(140) })).status, 200, "140 words and no emoji is fine");
    assertEquals((await call("profile-set", me.token, { display_name: "Ada", about_text: "a".repeat(141) })).status, 400);
    assertEquals((await call("profile-set", me.token, { display_name: "Ada", about_emoji: "👋👋" })).status, 400, "one emoji only");
    assertEquals((await call("profile-set", me.token, { display_name: "Ada", about_emoji: "x" })).status, 200, "a single character is accepted as the leading mark");

    // Cleared: both gone.
    const cleared = await call("profile-set", me.token, { display_name: "Ada" });
    assertEquals([cleared.body.about_emoji, cleared.body.about_text], [null, null]);
  });
});

Deno.test("the name is 1 to 40 characters", opts, async () => {
  await withUsers(1, async ([me]) => {
    assertEquals((await call("profile-set", me.token, { display_name: "n".repeat(40) })).status, 200);
    assertEquals((await call("profile-set", me.token, { display_name: "n".repeat(41) })).status, 400);
    assertEquals((await call("profile-set", me.token, { display_name: "   " })).status, 400);
  });
});

Deno.test("hide from search is honoured by users-find, and hides About and school from others", opts, async () => {
  await withUsers(2, async ([me, other]) => {
    const username = handle();
    await call("profile-set", me.token, { display_name: "Hidden H", username, school: "Bay", about_text: "private-ish", hide_from_search: false });
    assertEquals((await call("users-find", other.token, { query: username })).status, 200);
    await call("profile-set", me.token, { display_name: "Hidden H", username, school: "Bay", about_text: "private-ish", hide_from_search: true });
    assertEquals((await call("users-find", other.token, { query: username })).status, 404);
    const seen = (await call("profile-get", other.token, { user_id: me.id })).body.profile;
    assertEquals([seen.username, seen.school, seen.about_text, seen.display_name], [null, null, null, "Hidden H"]);
    assertEquals((await call("profile-get", me.token, {})).body.profile.hide_from_search, true, "you still see your own setting");
    await call("profile-set", me.token, { display_name: "Hidden H", username, school: "Bay", hide_from_search: false });
    assertEquals((await call("users-find", other.token, { query: username })).status, 200);
  });
});

Deno.test("a username that is taken says so, and your own can be kept", opts, async () => {
  await withUsers(2, async ([a, b]) => {
    const name = handle();
    assertEquals((await call("profile-set", a.token, { display_name: "A", username: name })).status, 200);
    const taken = await call("profile-set", b.token, { display_name: "B", username: name.toUpperCase() });
    assertEquals([taken.status, taken.body.error], [409, "username_taken"]);
    assertEquals((await call("profile-set", a.token, { display_name: "A2", username: name })).status, 200, "saving your own username again is fine");
  });
});

Deno.test("change password: the current one, an emailed code, then the new one", opts, async () => {
  const email = `pw-${crypto.randomUUID().slice(0, 12)}@example.invalid`;
  const oldPassword = "the old password 123";
  const newPassword = "the brand new password 456";
  const { data, error } = await admin.auth.admin.createUser({ email, password: oldPassword, email_confirm: true });
  if (error || !data.user) throw new Error("could not create the user");
  const id = data.user.id;
  try {
    const anon = createClient(API_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    const signedIn = await anon.auth.signInWithPassword({ email, password: oldPassword });
    const token = signedIn.data.session!.access_token;
    await admin.from("auth_proofs").upsert({ session_id: sessionIdOf(token), user_id: id, password_ok: true, code_ok: true, verified_at: new Date().toISOString() });

    // The current password must be right (and nothing is emailed otherwise).
    await clearMailbox(email);
    assertEquals((await call("password-change-start", token, { current_password: "not it at all" })).status, 401);
    assertEquals((await call("password-change-start", token, {})).status, 400);
    assertEquals((await call("password-change-start", null, { current_password: oldPassword })).status, 401);

    const started = Date.now() - 2000;
    assertEquals((await call("password-change-start", token, { current_password: oldPassword })).status, 200);
    const code = await emailedCode(email, started);

    // A wrong code, a weak password and a missing code are refused; the old password still works.
    const wrong = await call("password-change-verify", token, { code: code === "000000" ? "111111" : "000000", new_password: newPassword });
    assertEquals([wrong.status, wrong.body.error], [400, "bad_code"]);
    assertEquals((await call("password-change-verify", token, { code, new_password: "short" })).status, 400);
    assertEquals((await call("password-change-verify", token, { new_password: newPassword })).status, 400);
    assertEquals((await anon.auth.signInWithPassword({ email, password: oldPassword })).error, null, "nothing changed yet");

    // The right code with the new password changes it and returns a session that is verified.
    const done = await call("password-change-verify", token, { code, new_password: newPassword });
    assertEquals(done.status, 200, JSON.stringify(done.body));
    assertEquals((await call("profile-get", done.body.access_token, {})).status, 200, "the fresh session has both steps");
    assertNotEquals((await anon.auth.signInWithPassword({ email, password: oldPassword })).error, null, "the old password stops working");
    assertEquals((await anon.auth.signInWithPassword({ email, password: newPassword })).error, null);
    await pause();
  } finally {
    await admin.auth.admin.deleteUser(id);
  }
});

Deno.test("password change needs a fully signed-in session", opts, async () => {
  assertEquals((await call("password-change-start", null, { current_password: "x" })).status, 401);
  assertEquals((await call("password-change-verify", null, { code: "123456", new_password: "long enough password" })).status, 401);
  assert(true);
});
