// A smoke test against the STAGING project (run by ./supabase/smoke-staging.sh): two throwaway
// users, one sealed send, one fetch, one ack. The throwaway users are always deleted.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { call, ciphertext, deleteUser, newMasterKey, newUser, registerDevice, setAccessKey } from "./helpers.ts";

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
} finally {
  await deleteUser(alice);
  await deleteUser(bob);
  console.log("throwaway users deleted");
}
