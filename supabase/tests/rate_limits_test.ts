// LIME-166 (review finding F-07): the authenticated functions that had no limit of their own now have one per user. Run with ./supabase/test.sh.

import { assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { admin, call, deleteUser, newUser } from "./helpers.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };

/**
 * Calls until one is limited, for at most `max` more calls. The limits count in fixed windows, so a test that happens to straddle a window's
 * edge sees the count start again once: the limit still shows within one more window's worth of calls.
 */
async function untilLimited(max: number, once: () => Promise<{ status: number; body: any }>): Promise<{ status: number; body: any }> {
  let last = await once();
  for (let i = 0; i < max && last.status !== 429; i++) last = await once();
  return last;
}

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
      const over = await untilLimited(limit, () => call(name, user.token, body));
      assertEquals(over.status, 429);
      assertEquals(over.body.error, "rate_limited");
    } finally {
      await deleteUser(user);
    }
  });
}

// The password and code functions (LIME-166, item 8): per user for the two that have a session, per client address for the two that do not.
for (const [name, limit] of [["signup-set-password", 10], ["password-change-verify", 10]] as const) {
  Deno.test(`${name} is limited to ${limit} per ten minutes per user`, opts, async () => {
    const user = await newUser();
    try {
      for (let i = 0; i < limit; i++) {
        assertNotEquals((await call(name, user.token, {})).status, 429, `call ${i + 1} of ${limit} is not limited`);
      }
      const over = await untilLimited(limit, () => call(name, user.token, {}));
      assertEquals(over.status, 429);
      assertEquals(over.body.error, "rate_limited");
    } finally {
      await deleteUser(user);
    }
  });
}

for (const name of ["signup-verify", "reset-verify"]) {
  Deno.test(`${name} is limited to 60 per ten minutes per client address (no session)`, opts, async () => {
    await admin.from("rate_limits").delete().like("bucket", "verify:ip:%");
    const run = crypto.randomUUID().slice(0, 8);
    const same = { "cf-connecting-ip": "203.0.113.66" };   // one address for every call (the helper makes up a new one each time)
    try {
      // A fresh address each call and each run: a code that was tried five times is locked (also a 429, but not this limit).
      for (let i = 0; i < 60; i++) {
        const who = `nobody-${run}-${i}@example.org`;
        const res = await call(name, null, { email: who, identifier: who, code: "123456", new_password: "long enough password" }, same);
        assertNotEquals(res.body.error, "rate_limited", `call ${i + 1} of 60 is not limited: ${JSON.stringify(res.body)}`);
      }
      const over = await untilLimited(60, () => {
        const who = `nobody-${run}-over-${crypto.randomUUID().slice(0, 6)}@example.org`;
        return call(name, null, { email: who, identifier: who, code: "123456", new_password: "long enough password" }, same);
      });
      assertEquals(over.status, 429);
      assertEquals(over.body.error, "rate_limited");
    } finally {
      // The address bucket is shared with the other tests in this run and the next one: clear it.
      await admin.from("rate_limits").delete().like("bucket", "verify:ip:%");
    }
  });
}
