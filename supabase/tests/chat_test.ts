// LIME-95: finding a person by exact username or email, other people's public profiles, and the
// private per-device Realtime channel. Against the LOCAL stack: ./supabase/test.sh

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  admin, ANON_KEY, API_URL, call, ciphertext, deleteUser, newMasterKey, newUser, registerDevice, setAccessKey, type TestUser,
} from "./helpers.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };

async function withUsers<T>(count: number, fn: (users: TestUser[]) => Promise<T>): Promise<T> {
  const users = await Promise.all(Array.from({ length: count }, newUser));
  try {
    return await fn(users);
  } finally {
    await Promise.all(users.map(deleteUser));
  }
}

async function profile(user: TestUser, fields: { display_name: string; username?: string; school?: string; hide_from_search?: boolean }) {
  const { error } = await admin.from("profiles").insert({ user_id: user.id, ...fields });
  if (error) throw new Error(error.message);
}

const handle = () => `u${crypto.randomUUID().replaceAll("-", "").slice(0, 10)}`;

Deno.test("users-find: an exact username or email gives public fields only; nothing else matches", opts, async () => {
  await withUsers(2, async ([alice, bob]) => {
    const username = handle();
    await profile(alice, { display_name: "Alice A", username });
    await profile(bob, { display_name: "Bob B", username: handle(), school: "Bay School" });

    const byName = await call("users-find", alice.token, { query: `@${username.toUpperCase()}` });
    assertEquals(byName.status, 200);
    assertEquals(byName.body.display_name, "Alice A");
    assertEquals(byName.body.is_self, true);

    const byEmail = await call("users-find", alice.token, { query: ` ${bob.email.toUpperCase()} ` });
    assertEquals(byEmail.status, 200);
    assertEquals(byEmail.body.user_id, bob.id);
    assertEquals(byEmail.body.school, "Bay School");
    assertEquals(byEmail.body.is_self, false);
    assertEquals(Object.keys(byEmail.body).sort(), ["display_name", "is_self", "school", "user_id", "username"], "public fields only, no email");

    // No partial matches, no listing.
    assertEquals((await call("users-find", alice.token, { query: username.slice(0, 6) })).status, 404);
    assertEquals((await call("users-find", alice.token, { query: bob.email.split("@")[0] + "@example" })).status, 400);
    assertEquals((await call("users-find", alice.token, { query: "nobody.here" })).status, 404);
    assertEquals((await call("users-find", alice.token, { query: "ab" })).status, 400);
    assertEquals((await call("users-find", null, { query: username })).status, 401);
  });
});

Deno.test("users-find: someone hidden from search is not found, and an account with no profile is not found", opts, async () => {
  await withUsers(3, async ([alice, hidden, bare]) => {
    const username = handle();
    await profile(alice, { display_name: "Alice" });
    await profile(hidden, { display_name: "Hidden H", username, hide_from_search: true });
    assertEquals((await call("users-find", alice.token, { query: username })).status, 404);
    assertEquals((await call("users-find", alice.token, { query: hidden.email })).status, 404);
    assertEquals((await call("users-find", alice.token, { query: bare.email })).status, 404, "no profile yet");
  });
});

Deno.test("users-find is rate-limited", opts, async () => {
  await withUsers(1, async ([alice]) => {
    await profile(alice, { display_name: "Alice" });
    let limited = 0;
    for (let i = 0; i < 34; i++) {
      if ((await call("users-find", alice.token, { query: "nobody.here" })).status === 429) limited++;
    }
    assert(limited > 0, "the 31st lookup in a minute is refused");
  });
});

Deno.test("profile-get of another person: public fields only; hidden shows the name only", opts, async () => {
  await withUsers(3, async ([alice, bob, hidden]) => {
    await profile(alice, { display_name: "Alice" });
    await profile(bob, { display_name: "Bob B", username: "bob.b" + handle().slice(0, 4), school: "Bay School" });
    await profile(hidden, { display_name: "Hidden H", username: handle(), school: "Secret School", hide_from_search: true });

    const seen = await call("profile-get", alice.token, { user_id: bob.id });
    assertEquals(seen.status, 200);
    assertEquals(seen.body.profile.display_name, "Bob B");
    assertEquals(seen.body.profile.school, "Bay School");
    assertEquals(Object.keys(seen.body.profile).sort(), ["display_name", "school", "user_id", "username"], "never an email or phone");

    const masked = await call("profile-get", alice.token, { user_id: hidden.id });
    assertEquals(masked.body.profile.display_name, "Hidden H");
    assertEquals(masked.body.profile.username, null);
    assertEquals(masked.body.profile.school, null);

    assertEquals((await call("profile-get", alice.token, { user_id: crypto.randomUUID() })).status, 404);
    assertEquals((await call("profile-get", alice.token, { user_id: "not-a-uuid" })).status, 400);
    assertEquals((await call("profile-get", alice.token, {})).body.profile.display_name, "Alice", "no user_id: your own");
    assertEquals((await call("profile-get", null, { user_id: bob.id })).status, 401);
  });
});

async function privateClient(token: string | null) {
  const client = createClient(API_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  if (token) await client.realtime.setAuth(token); // before joining: the join must carry the user's token
  return client;
}

/** Joins a private device channel; resolves what the join did and the first nudge, if any. */
async function listen(token: string | null, deviceId: string, onJoined: () => Promise<void> = async () => {}) {
  const client = await privateClient(token);
  return await new Promise<{ status: string; nudge: unknown; close: () => Promise<unknown> }>((resolve) => {
    let status = "";
    let nudge: unknown = null;
    const finish = () => resolve({ status, nudge, close: () => client.removeAllChannels() });
    const timer = setTimeout(finish, 6000);
    const channel = client.channel(`device:${deviceId}`, { config: { private: true } });
    channel.on("broadcast", { event: "new" }, (message: unknown) => {
      nudge = message;
      clearTimeout(timer);
      finish();
    }).subscribe(async (s: string) => {
      if (status !== "SUBSCRIBED") status = s;
      if (s === "SUBSCRIBED") await onJoined();
      else if (s === "CHANNEL_ERROR" || s === "TIMED_OUT" || s === "CLOSED") { clearTimeout(timer); finish(); }
    });
  });
}

Deno.test("Realtime: the nudge is on a private channel only the device's owner can join", opts, async () => {
  await withUsers(2, async ([bob, mallory]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const key = await setAccessKey(bob);
    const send = () => call("send", null, { ciphertext: ciphertext(), recipients: [{ to_device: device.deviceId, access: { sealed: key } }] });

    // The owner joins and is nudged, with no content.
    const owner = await listen(bob.token, device.deviceId, async () => { await send(); });
    await owner.close();
    assertEquals(owner.status, "SUBSCRIBED");
    const nudge = owner.nudge as { payload?: unknown } | null; // supabase-js hands over the payload itself or wrapped
    assertEquals(nudge?.payload ?? nudge, { type: "new" }, "the nudge carries no content");

    // Another signed-in user, and a client with only the public key, are refused.
    for (const [label, token] of [["another user", mallory.token], ["anon", null]] as const) {
      const stranger = await listen(token, device.deviceId);
      await stranger.close();
      assertNotEquals(stranger.status, "SUBSCRIBED", `${label} cannot join someone else's channel`);
      assertEquals(stranger.nudge, null);
    }
  });
});
