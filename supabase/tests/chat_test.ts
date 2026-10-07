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
    assertEquals(Object.keys(byEmail.body).sort(), ["about_emoji", "about_text", "display_name", "is_self", "school", "user_id", "username"], "public fields only, no email");

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
    assertEquals(Object.keys(seen.body.profile).sort(), ["about_emoji", "about_text", "display_name", "school", "user_id", "username"], "never an email or phone");

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

// ---------------------------------------------------------------- LIME-95-fix: replacing an account's keys

import { keysReplacedNotice, sendNotice } from "../functions/_shared/notify.ts";
import { sha256Bytes } from "./helpers.ts";

const hex = (bytes: Uint8Array) => Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");

Deno.test("a verified session with new keys replaces the account's keys: old devices revoked, mail removed, senders told", opts, async () => {
  await withUsers(2, async ([owner, sender]) => {
    const oldMaster = await newMasterKey();
    const oldDevice = await registerDevice(owner, oldMaster);
    const accessKey = await setAccessKey(owner);

    // Two items wait for the old device: one identified (from `sender`), one sealed (no known sender).
    const identified = ciphertext(80);
    const sealed = ciphertext(90);
    assertEquals((await call("send", sender.token, { ciphertext: identified, recipients: [{ to_device: oldDevice.deviceId, access: { identified: true } }] })).status, 200);
    assertEquals((await call("send", null, { ciphertext: sealed, recipients: [{ to_device: oldDevice.deviceId, access: { sealed: accessKey } }] })).status, 200);
    assertEquals((await call("mailbox-fetch", owner.token, { device_id: oldDevice.deviceId, after: 0 })).body.items.length, 2);

    // A phone with brand-new keys registers from the same verified session.
    const newMaster = await newMasterKey();
    const newDevice = await registerDevice(owner, newMaster);
    assertNotEquals(newDevice.deviceId, oldDevice.deviceId);

    // Only the new device is listed, under the new master key.
    const listed = await call("users-devices", sender.token, { user_id: owner.id });
    assertEquals(listed.body.master_key, newMaster.publicKey);
    assertEquals(listed.body.devices.map((d: { device_id: string }) => d.device_id), [newDevice.deviceId]);

    // The old device is refused everywhere, and nothing can be sent to it.
    assertEquals((await call("mailbox-fetch", owner.token, { device_id: oldDevice.deviceId, after: 0 })).status, 403);
    assertEquals((await call("send", sender.token, { ciphertext: ciphertext(70), recipients: [{ to_device: oldDevice.deviceId, access: { identified: true } }] })).status, 404);
    // Its waiting mail is gone (nobody holds the keys to read it).
    const { data: left } = await admin.from("mailbox_items").select("cursor").eq("to_device", oldDevice.deviceId);
    assertEquals(left?.length, 0);

    // The identified sender is told which of its messages were never delivered (by hash); the sealed
    // sender cannot be told. The notice is handed over once.
    const told = await call("undelivered-take", sender.token, {});
    assertEquals(told.status, 200);
    const expected = hex(await sha256Bytes(Uint8Array.from(atob(identified), (c) => c.charCodeAt(0))));
    assertEquals(told.body.hashes, [expected]);
    assertEquals((await call("undelivered-take", sender.token, {})).body.hashes, []);
    assertEquals((await call("undelivered-take", owner.token, {})).body.hashes, [], "the owner is not a sender here");
    assertEquals((await call("undelivered-take", null, {})).status, 401);
  });
});

Deno.test("a second device with the SAME master key is added without any reset", opts, async () => {
  await withUsers(1, async ([owner]) => {
    const master = await newMasterKey();
    const first = await registerDevice(owner, master);
    const second = await registerDevice(owner, master);
    const { data } = await admin.from("devices").select("device_id, revoked_at").eq("user_id", owner.id);
    assertEquals(data?.length, 2);
    assert(data?.every((d) => d.revoked_at === null), "neither is revoked");
    assertEquals((await call("mailbox-fetch", owner.token, { device_id: first.deviceId, after: 0 })).status, 200);
    assertEquals((await call("mailbox-fetch", owner.token, { device_id: second.deviceId, after: 0 })).status, 200);
  });
});

Deno.test("the keys-replaced notice reads as asked and goes out only when a mail key is configured", opts, async () => {
  const notice = keysReplacedNotice(new Date("2026-10-07T05:00:00Z"));
  assertEquals(notice.subject, "A new phone signed in to Lime");
  assert(notice.text.startsWith("A new phone signed in and replaced your Lime keys. If this wasn't you, reset your password."));

  Deno.env.delete("LIME_NOTIFY_RESEND_API_KEY");
  assertEquals(await sendNotice("someone@example.invalid", notice), false, "no key: nothing is sent, nothing fails");

  const received: { auth: string | null; body: Record<string, unknown> }[] = [];
  const server = Deno.serve({ port: 0, onListen: () => {} }, async (req) => {
    received.push({ auth: req.headers.get("authorization"), body: await req.json() });
    return new Response("{}", { status: 200 });
  });
  try {
    Deno.env.set("LIME_NOTIFY_RESEND_API_KEY", "test-key");
    Deno.env.set("LIME_NOTIFY_URL", `http://127.0.0.1:${server.addr.port}/emails`);
    assertEquals(await sendNotice("someone@example.invalid", notice), true);
    assertEquals(received.length, 1);
    assertEquals(received[0].auth, "Bearer test-key");
    assertEquals(received[0].body.to, ["someone@example.invalid"]);
    assertEquals(received[0].body.subject, "A new phone signed in to Lime");
    assertEquals(typeof received[0].body.from, "string");
  } finally {
    Deno.env.delete("LIME_NOTIFY_RESEND_API_KEY");
    Deno.env.delete("LIME_NOTIFY_URL");
    await server.shutdown();
  }
});
