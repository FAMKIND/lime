// A smoke test against the STAGING project (run by ./supabase/smoke-staging.sh): two throwaway
// users, one sealed send, one fetch, one ack. The throwaway users are always deleted.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { createClient } from "npm:@supabase/supabase-js@2";
import { ANON_KEY, API_URL, call, ciphertext, deleteUser, newMasterKey, newUnverifiedUser, newUser, registerDevice, setAccessKey } from "./helpers.ts";

const alice = await newUser(); // the sender (never needs a token for a sealed send)
const bob = await newUser();
try {
  const device = await registerDevice(bob, await newMasterKey());
  const accessKey = await setAccessKey(bob);
  const payload = ciphertext(96);

  const sent = await call("send", null, { ciphertext: payload, recipients: [{ to_device: device.deviceId, access: { sealed: accessKey } }] });
  assertEquals(sent.status, 200, "sealed send");
  assertEquals(sent.body.stored, 1);

  const fetched = await call("mailbox-fetch", bob.token, { device_id: device.deviceId, after: 0 });
  assertEquals(fetched.status, 200, "fetch");
  assertEquals(fetched.body.items.length, 1);
  assertEquals(fetched.body.items[0].ciphertext, payload);
  assert(fetched.body.items[0].identified === undefined, "a sealed item has no sender");

  const acked = await call("mailbox-ack", bob.token, { device_id: device.deviceId, up_to_cursor: fetched.body.items[0].cursor });
  assertEquals(acked.status, 200, "ack");
  assertEquals(acked.body.deleted, 1);
  assertEquals((await call("mailbox-fetch", bob.token, { device_id: device.deviceId, after: 0 })).body.items.length, 0);
  console.log("staging smoke test passed: sealed send, fetch, ack");

  // The two-step enforcement and the account functions that need no email (LIME-94).
  const passwordOnly = await newUnverifiedUser(); // a signed-in session that has not passed both steps
  try {
    assertEquals((await call("profile-get", passwordOnly.token, {})).status, 403, "an unverified session is refused");
    assertEquals((await call("users-lookup", passwordOnly.token, { email: bob.email })).status, 403);
    assertEquals((await call("profile-get", bob.token, {})).status, 200, "a verified session works");
    assertEquals((await call("profile-set", bob.token, { display_name: "Smoke Test" })).status, 200);
    assertEquals((await call("identify", null, { identifier: "someone-new@example.invalid" })).body.exists, false);
    assertEquals((await call("identify", null, { identifier: bob.email })).body.exists, true);
    assertEquals((await call("identify", null, { identifier: "no.such.username" })).status, 404);
    assertEquals((await call("signin-password", null, { identifier: bob.email, password: "wrong password here" })).status, 401);
    console.log("staging account checks passed: verified sessions only, identify, profile");

    // Finding a person, their public profile, and the private per-device nudge (LIME-95).
    const found = await call("users-find", alice.token, { query: bob.email });
    assertEquals(found.status, 200, "users-find by exact email");
    assertEquals(found.body.display_name, "Smoke Test");
    assertEquals((await call("users-find", alice.token, { query: "no.such.person.here" })).status, 404);
    const profile = await call("profile-get", alice.token, { user_id: bob.id });
    assertEquals(profile.body.profile.display_name, "Smoke Test");
    assert(!("email" in profile.body.profile), "a public profile has no email");

    const listen = async (token: string, onJoined: () => Promise<void> = async () => {}) => {
      const client = createClient(API_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
      await client.realtime.setAuth(token);
      const outcome = await new Promise<{ joined: boolean; nudge: unknown }>((resolve) => {
        let joined = false;
        let nudge: unknown = null;
        const finish = () => resolve({ joined, nudge });
        const timer = setTimeout(finish, 8000);
        client.channel(`device:${device.deviceId}`, { config: { private: true } })
          .on("broadcast", { event: "new" }, (m: unknown) => { nudge = m; clearTimeout(timer); finish(); })
          .subscribe(async (status: string) => {
            if (status === "SUBSCRIBED") { joined = true; await onJoined(); }
            else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") { if (!joined) { clearTimeout(timer); finish(); } }
          });
      });
      await client.removeAllChannels();
      return outcome;
    };
    const owner = await listen(bob.token, async () => {
      await call("send", null, { ciphertext: ciphertext(), recipients: [{ to_device: device.deviceId, access: { sealed: accessKey } }] });
    });
    assert(owner.joined && owner.nudge !== null, "the device's owner joins its private channel and is nudged");
    const stranger = await listen(alice.token);
    assert(!stranger.joined && stranger.nudge === null, "another user cannot join someone elses channel");
    console.log("staging chat checks passed: find, public profile, private nudge");
  } finally {
    await deleteUser(passwordOnly);
  }
} finally {
  await deleteUser(alice);
  await deleteUser(bob);
  console.log("throwaway users deleted");
}
