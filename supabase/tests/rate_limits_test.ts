// LIME-166 (review finding F-07): the authenticated functions that had no limit of their own now have one per user. Run with ./supabase/test.sh.

import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { call, deleteUser, newUser } from "./helpers.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };

// [function, limit per minute (the defaults in _shared/config.ts), a body that passes the limit check and may then fail validation]
const limited: [string, number, Record<string, unknown>][] = [
  ["profile-set", 30, {}],
  ["delivery-access-set", 20, {}],
  ["keys-upload", 30, {}],
  ["undelivered-take", 60, {}],
  ["users-devices", 120, { user_id: "00000000-0000-4000-8000-000000000000" }],
  ["mailbox-ack", 120, { device_id: "00000000-0000-4000-8000-000000000000", up_to_cursor: 0 }],
];

for (const [name, limit, body] of limited) {
  Deno.test(`${name} is limited to ${limit} a minute per user and says so with a 429`, opts, async () => {
    const user = await newUser();
    try {
      for (let i = 0; i < limit; i++) {
        assertNotEquals((await call(name, user.token, body)).status, 429, `call ${i + 1} of ${limit} is not limited`);
      }
      const over = await call(name, user.token, body);
      assertEquals(over.status, 429);
      assertEquals(over.body.error, "rate_limited");
    } finally {
      await deleteUser(user);
    }
  });
}
