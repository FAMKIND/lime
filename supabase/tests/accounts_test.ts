// Sign-up, sign-in with a password AND an emailed code, forgot password, profiles: LIME-94, against
// the LOCAL stack (the emailed codes are read from its mail catcher). Run with ./supabase/test.sh.

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { toBase64 } from "../functions/_shared/bytes.ts";
import {
  admin, ANON_KEY, API_URL, call, clearMailbox, emailedCode, newMasterKey, pause, randomBytes, registerDevice, sessionIdOf,
} from "./helpers.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };
const PASSWORD = "correct horse battery";

type Tokens = { access_token: string; refresh_token: string; user_id: string };

const created: string[] = [];
function newEmail(): string {
  return `acct-${crypto.randomUUID().slice(0, 12)}@example.invalid`;
}

async function cleanup() {
  for (const id of created.splice(0)) await admin.auth.admin.deleteUser(id);
}

/** The whole sign-up flow; returns a VERIFIED session. */
async function signUp(email: string, extra: { name?: string; username?: string } = {}): Promise<Tokens> {
  await clearMailbox(email);
  const started = Date.now() - 2000;
  const start = await call("signup-start", null, { email });
  assertEquals(start.status, 200, JSON.stringify(start.body));
  const code = await emailedCode(email, started);
  const verified = await call("signup-verify", null, { email, code });
  assertEquals(verified.status, 200, JSON.stringify(verified.body));
  const codeOnly = verified.body as Tokens;
  created.push(codeOnly.user_id);
  const set = await call("signup-set-password", codeOnly.access_token, { password: PASSWORD });
  assertEquals(set.status, 200, JSON.stringify(set.body));
  const tokens = set.body as Tokens; // a fresh session that has passed both steps
  const profile = await call("profile-set", tokens.access_token, { display_name: extra.name ?? "Test Teacher", username: extra.username });
  assertEquals(profile.status, 200, JSON.stringify(profile.body));
  return tokens;
}

async function signInPassword(identifier: string, password = PASSWORD) {
  await pause(); // Auth sends at most one email a second to an address
  return await call("signin-password", null, { identifier, password });
}

async function canRegisterDevice(token: string, master?: Awaited<ReturnType<typeof newMasterKey>>): Promise<number> {
  master ??= await newMasterKey();
  const deviceId = crypto.randomUUID();
  const identityKey = toBase64(randomBytes(32));
  const signingKey = toBase64(randomBytes(32));
  const res = await call("devices-register", token, {
    device_id: deviceId, identity_key: identityKey, signing_key: signingKey, master_key: master.publicKey,
    master_signature: await master.sign(`lime-device-v1\n${deviceId}\n${identityKey}\n${signingKey}`),
  });
  return res.status;
}

Deno.test("sign-up: email, emailed code, password, profile, then a device can register", opts, async () => {
  try {
    const email = newEmail();
    await clearMailbox(email);
    const started = Date.now() - 2000;
    assertEquals((await call("signup-start", null, { email })).status, 200);
    const code = await emailedCode(email, started);

    // A wrong code is refused; the right one gives a session that has proven the email only.
    assertEquals((await call("signup-verify", null, { email, code: code === "000000" ? "111111" : "000000" })).body.error, "bad_code");
    const verified = await call("signup-verify", null, { email, code });
    assertEquals(verified.status, 200);
    const tokens = verified.body as Tokens;
    created.push(tokens.user_id);
    assertEquals(await canRegisterDevice(tokens.access_token), 403, "a code-only session cannot register a device");

    // The password: too short is refused; a good one finishes both steps.
    assertEquals((await call("signup-set-password", tokens.access_token, { password: "short" })).body.error, "weak_password");
    const set = await call("signup-set-password", tokens.access_token, { password: PASSWORD });
    assertEquals(set.status, 200);
    const verifiedTokens = set.body as Tokens;
    assertNotEquals(sessionIdOf(verifiedTokens.access_token), sessionIdOf(tokens.access_token), "setting the password ends the old session");
    tokens.access_token = verifiedTokens.access_token;

    // The profile (name, optional username and school), then the device.
    const profile = await call("profile-set", tokens.access_token, { display_name: "  Ada Lovelace  ", username: "@Ada.L", school: "Analytical Academy" });
    assertEquals(profile.body, { user_id: tokens.user_id, display_name: "Ada Lovelace", username: "Ada.L", school: "Analytical Academy", hide_from_search: false });
    assertEquals((await call("profile-get", tokens.access_token, {})).body.profile.username, "Ada.L");
    // Once the account has a profile, this route cannot change its password again.
    assertEquals((await call("signup-set-password", tokens.access_token, { password: PASSWORD + "x" })).status, 409);
    assertEquals(await canRegisterDevice(tokens.access_token), 201, "after both steps a device registers");

    // An existing address cannot sign up again.
    assertEquals((await call("signup-start", null, { email })).body.error, "account_exists");
  } finally {
    await cleanup();
  }
});

Deno.test("sign-in by email and by username: password, then a new emailed code", opts, async () => {
  try {
    const email = newEmail();
    await signUp(email, { username: "ada_sign.in" });
    const master = await newMasterKey(); // an account has one master key; every device is signed by it

    for (const identifier of [email, email.toUpperCase(), "ada_sign.in", "@Ada_Sign.In"]) {
      await clearMailbox(email);
      const started = Date.now() - 2000;
      const signedIn = await signInPassword(identifier);
      assertEquals(signedIn.status, 200, `${identifier}: ${JSON.stringify(signedIn.body)}`);
      assertEquals(signedIn.body.masked_email, `${email[0]}•••@example.invalid`, "the confirmation hint is masked");
      const token = signedIn.body.access_token as string;

      // Password only: nothing works yet.
      assertEquals(await canRegisterDevice(token), 403, "a password-only session cannot register a device");
      assertEquals((await call("users-lookup", token, { email })).status, 403);
      assertEquals((await call("profile-get", token, {})).status, 403);

      // A wrong code, then the right one.
      const code = await emailedCode(email, started);
      assertEquals((await call("code-verify", token, { code: code === "000000" ? "111111" : "000000" })).body.error, "bad_code");
      assertEquals((await call("code-verify", token, { code })).status, 200);
      assertEquals((await call("profile-get", token, {})).status, 200, "both steps done: the session works");
      assertEquals(await canRegisterDevice(token, master), 201);
    }

    // A wrong password, an unknown email and an unknown username all look the same.
    for (const [identifier, password] of [[email, "not the password"], ["nobody@example.invalid", PASSWORD], ["no_such_user", PASSWORD]]) {
      const res = await signInPassword(identifier, password);
      assertEquals(res.status, 401);
      assertEquals(res.body.error, "invalid_credentials");
    }
  } finally {
    await cleanup();
  }
});

Deno.test("a code-only session made straight with Supabase Auth cannot register a device either", opts, async () => {
  try {
    const email = newEmail();
    const tokens = await signUp(email);
    // The attacker has the emailed code but not the password: they use Auth's own email sign-in.
    await clearMailbox(email);
    await pause();
    const started = Date.now() - 2000;
    const auth = createClient(API_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    assertEquals((await auth.auth.signInWithOtp({ email, options: { shouldCreateUser: false } })).error, null);
    const code = await emailedCode(email, started);
    const { data, error } = await auth.auth.verifyOtp({ email, token: code, type: "email" });
    assertEquals(error, null);
    const sneaky = data.session!.access_token;
    assertNotEquals(sessionIdOf(sneaky), sessionIdOf(tokens.access_token));
    assertEquals(await canRegisterDevice(sneaky), 403, "no proof record: nothing works");
    assertEquals((await call("users-lookup", sneaky, { email })).status, 403);
    // The same for a password-only session made straight with Auth (no emailed code).
    const direct = await auth.auth.signInWithPassword({ email, password: PASSWORD });
    assertEquals(await canRegisterDevice(direct.data.session!.access_token), 403);
  } finally {
    await cleanup();
  }
});

Deno.test("a wrong code is limited after 5 tries, and a resend starts again", opts, async () => {
  try {
    const email = newEmail();
    await signUp(email);
    await clearMailbox(email);
    const started = Date.now() - 2000;
    const signedIn = await signInPassword(email);
    const token = signedIn.body.access_token as string;
    const good = await emailedCode(email, started);
    const wrong = good === "123456" ? "654321" : "123456";

    for (let i = 1; i <= 5; i++) {
      const res = await call("code-verify", token, { code: wrong });
      assertEquals(res.body.error, "bad_code", `try ${i}`);
    }
    // The 6th is locked, even with the right code.
    const locked = await call("code-verify", token, { code: good });
    assertEquals(locked.status, 429);
    assertEquals(locked.body.error, "locked");

    // Asking for another code right away is too soon...
    assertEquals((await call("code-resend", token, {})).body.error, "too_soon");
    // ...but after 30 seconds it works, and the count of wrong tries starts again.
    await admin.from("code_challenges").update({ sent_at: new Date(Date.now() - 31_000).toISOString() })
      .eq("challenge_key", `session:${sessionIdOf(token)}`);
    await clearMailbox(email);
    await pause();
    const resentAt = Date.now() - 2000;
    assertEquals((await call("code-resend", token, {})).status, 200);
    const fresh = await emailedCode(email, resentAt);
    assertEquals((await call("code-verify", token, { code: fresh })).status, 200);
    assertEquals((await call("profile-get", token, {})).status, 200);

    // The sign-up code is limited the same way (per address).
    const other = newEmail();
    await clearMailbox(other);
    const otherStarted = Date.now() - 2000;
    assertEquals((await call("signup-start", null, { email: other })).status, 200);
    const otherCode = await emailedCode(other, otherStarted);
    const otherWrong = otherCode === "123456" ? "654321" : "123456";
    for (let i = 0; i < 5; i++) assertEquals((await call("signup-verify", null, { email: other, code: otherWrong })).body.error, "bad_code");
    assertEquals((await call("signup-verify", null, { email: other, code: otherCode })).status, 429);
    const { data: leftover } = await admin.rpc("lookup_user_id_by_email", { p_email: other });
    if (leftover) created.push(leftover);
  } finally {
    await cleanup();
  }
});

Deno.test("forgot password: a code and a new password, and the old password stops working", opts, async () => {
  try {
    const email = newEmail();
    const username = `reset${crypto.randomUUID().slice(0, 8)}`;
    await signUp(email, { username });

    // An unknown address gets the same answer and no email.
    await clearMailbox("ghost@example.invalid");
    assertEquals((await call("reset-start", null, { email: "ghost@example.invalid" })).body, { ok: true });

    await clearMailbox(email);
    await pause();
    const started = Date.now() - 2000;
    assertEquals((await call("reset-start", null, { identifier: email })).body, { ok: true });
    const code = await emailedCode(email, started);
    const newPassword = "a brand new password";
    assertEquals((await call("reset-verify", null, { identifier: email, code, new_password: "short" })).body.error, "weak_password");
    const reset = await call("reset-verify", null, { identifier: email, code, new_password: newPassword });
    assertEquals(reset.status, 200, JSON.stringify(reset.body));
    // Code plus the new password were both proven: the session is verified.
    assertEquals((await call("profile-get", reset.body.access_token, {})).status, 200);

    assertEquals((await signInPassword(email, PASSWORD)).status, 401, "the old password no longer works");
    assertEquals((await signInPassword(email, newPassword)).status, 200);

    // The same by username: the server finds the address, the phone never needs it.
    await clearMailbox(email);
    await pause();
    const byUsernameAt = Date.now() - 2000;
    assertEquals((await call("reset-start", null, { identifier: `@${username}` })).body, { ok: true });
    const usernameCode = await emailedCode(email, byUsernameAt);
    const again = await call("reset-verify", null, { identifier: username, code: usernameCode, new_password: "yet another password" });
    assertEquals(again.status, 200, JSON.stringify(again.body));
    assertEquals((await signInPassword(username, "yet another password")).status, 200);
  } finally {
    await cleanup();
  }
});

Deno.test("profiles: username rules, uniqueness ignoring case, and what identify reveals", opts, async () => {
  try {
    const a = await signUp(newEmail(), { username: "teacher.one" });
    const b = await signUp(newEmail());

    for (const bad of ["ab", "has space", ".dot", "dot.", "admin", "x".repeat(21)]) {
      assertEquals((await call("profile-set", b.access_token, { display_name: "B", username: bad })).body.error, "bad_username", bad);
    }
    assertEquals((await call("profile-set", b.access_token, { display_name: "B", username: "TEACHER.ONE" })).body.error, "username_taken");
    assertEquals((await call("profile-set", b.access_token, { display_name: "" })).status, 400);
    assertEquals((await call("profile-set", b.access_token, { display_name: "B", username: "teacher.two", hide_from_search: true })).body.hide_from_search, true);

    // identify: an email says whether it has an account; a username gives only a masked hint.
    const known = newEmail();
    assertEquals((await call("identify", null, { identifier: "someone-new@example.invalid" })).body.exists, false);
    const username = await call("identify", null, { identifier: "@Teacher.One" });
    assertEquals(username.status, 200);
    assert(/^.•••@example\.invalid$/.test(username.body.hint), username.body.hint);
    assertEquals(Object.keys(username.body).sort(), ["hint", "kind"], "no full email, no user id");
    assertEquals((await call("identify", null, { identifier: "nobody.here" })).status, 404);
    assertEquals((await call("identify", null, { identifier: "ab" })).status, 404);
    assertNotEquals(known, "");
  } finally {
    await cleanup();
  }
});

Deno.test("identify is rate-limited per address", opts, async () => {
  let tripped = 0;
  for (let i = 0; i < 35; i++) {
    const res = await fetch(`${API_URL}/functions/v1/identify`, {
      method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "203.0.113.77" },
      body: JSON.stringify({ identifier: "rate.limit.check" }),
    });
    if (res.status === 429) tripped++;
    await res.text();
  }
  assert(tripped > 0, "the identify limit trips");
});

Deno.test("the existing functions refuse a session that is not verified", opts, async () => {
  try {
    const email = newEmail();
    await signUp(email);
    const signedIn = await signInPassword(email); // password step only
    const token = signedIn.body.access_token as string;
    for (const [fn, body] of [
      ["users-devices", { user_id: crypto.randomUUID() }], ["keys-claim", { user_id: crypto.randomUUID() }],
      ["delivery-access-set", { access_key_hash: toBase64(randomBytes(32)) }],
      ["mailbox-fetch", { device_id: crypto.randomUUID() }], ["keys-upload", { device_id: crypto.randomUUID(), one_time_keys: [] }],
      ["send", { ciphertext: "AAAA", recipients: [{ to_device: crypto.randomUUID(), access: { identified: true } }] }],
    ] as const) {
      const res = await call(fn, token, body);
      assertEquals(res.status, 403, `${fn} must require a verified session`);
    }
    // And no token at all is still 401.
    assertEquals((await call("profile-get", null, {})).status, 401);
    await registerDevice; // (kept imported for the shared helpers)
  } finally {
    await cleanup();
  }
});

Deno.test("a code of 6 to 8 digits is accepted as an answer (the hosted setting once sent 8)", opts, async () => {
  try {
    const email = newEmail();
    await signUp(email);
    await clearMailbox(email);
    const started = Date.now() - 2000;
    const signedIn = await signInPassword(email);
    const token = signedIn.body.access_token as string;
    const real = await emailedCode(email, started);
    // An 8-digit answer is checked like any other, not refused as the wrong length.
    const eight = real.length === 8 ? "00000000" : "12345678";
    assertEquals((await call("code-verify", token, { code: eight })).body.error, "bad_code");
    // Too short or too long is still a bad request, and not counted as a try.
    assertEquals((await call("code-verify", token, { code: "12345" })).body.error, "bad_request");
    assertEquals((await call("code-verify", token, { code: "123456789" })).body.error, "bad_request");
    // The code that was really emailed (whatever its length) is accepted.
    assertEquals((await call("code-verify", token, { code: real })).status, 200);
  } finally {
    await cleanup();
  }
});

Deno.test("a rate-limited code send is reported plainly, never as a code that was sent", opts, async () => {
  try {
    const email = newEmail();
    await signUp(email);
    await clearMailbox(email);
    await pause();
    // The first sign-in sends a code; asking again at once is refused by Auth's per-address interval.
    const first = await call("signin-password", null, { identifier: email, password: PASSWORD });
    assertEquals(first.status, 200);
    const second = await call("signin-password", null, { identifier: email, password: PASSWORD });
    assertEquals(second.status, 429, JSON.stringify(second.body));
    assertEquals(second.body.error, "too_soon");
    assert(/^Please wait \d+ seconds before asking for another code\.$/.test(second.body.message), second.body.message);
    assertEquals(second.body.access_token, undefined, "no session is handed out when no code went out");

    // Forgot password: the second request at once is reported too (for an existing account).
    await pause();
    assertEquals((await call("reset-start", null, { identifier: email })).status, 200);
    const again = await call("reset-start", null, { identifier: email });
    assertEquals(again.status, 429);
    assertEquals(again.body.error, "too_soon");
    // A sign-up of a brand new address likewise.
    const fresh = newEmail();
    assertEquals((await call("signup-start", null, { email: fresh })).status, 200);
    const freshAgain = await call("signup-start", null, { email: fresh });
    assertEquals(freshAgain.status, 429);
    assertEquals(freshAgain.body.error, "too_soon");
    // Until the code is entered the address is still new, so it can ask again (Resend) after the wait.
    assertEquals((await call("identify", null, { identifier: fresh })).body.exists, false);
    await pause();
    await clearMailbox(fresh);
    const resentAt = Date.now() - 2000;
    assertEquals((await call("signup-start", null, { email: fresh })).status, 200, "an unconfirmed address may ask for a new code");
    const resentCode = await emailedCode(fresh, resentAt);
    assertEquals((await call("signup-verify", null, { email: fresh, code: resentCode })).status, 200);
    assertEquals((await call("identify", null, { identifier: fresh })).body.exists, true, "a confirmed address is an account");
    const { data } = await admin.rpc("lookup_user_id_by_email", { p_email: fresh });
    if (data) created.push(data);
  } finally {
    await cleanup();
  }
});
