// API v2 core against the local Supabase stack. Run with ./supabase/test.sh.

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { createClient } from "npm:@supabase/supabase-js@2";
import postgres from "npm:postgres@3";
import {
  admin, ANON_KEY, API_URL, call, ciphertext, DB_URL, deleteUser, newMasterKey, newUser, otk, randomBytes,
  registerDevice, setAccessKey, type TestUser,
} from "./helpers.ts";
import { toBase64 } from "../functions/_shared/bytes.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };
const TABLES = ["master_keys", "devices", "one_time_keys", "mailbox_items", "delivery_access", "rate_limits"];

async function withUsers<T>(count: number, fn: (users: TestUser[]) => Promise<T>): Promise<T> {
  const users = await Promise.all(Array.from({ length: count }, newUser));
  try {
    return await fn(users);
  } finally {
    await Promise.all(users.map(deleteUser));
  }
}

async function fetchItems(user: TestUser, deviceId: string, after = 0) {
  return await call("mailbox-fetch", user.token, { device_id: deviceId, after });
}

Deno.test("register, upload keys, claim: a key is claimed once and the count drops", opts, async () => {
  await withUsers(2, async ([alice, bob]) => {
    const master = await newMasterKey();
    const device = await registerDevice(bob, master);

    // The signature is verified: a bad one is refused.
    const bad = await call("devices-register", bob.token, {
      device_id: crypto.randomUUID(), identity_key: toBase64(randomBytes(32)), signing_key: toBase64(randomBytes(32)),
      master_key: master.publicKey, master_signature: toBase64(randomBytes(64)),
    });
    assertEquals(bad.status, 400);
    assertEquals(bad.body.error, "bad_signature");

    // Uploading 5 keys reports 5 remaining; uploading the same ids again adds nothing.
    const keys = otk(5);
    const up = await call("keys-upload", bob.token, { device_id: device.deviceId, one_time_keys: keys });
    assertEquals(up.status, 200);
    assertEquals(up.body.remaining_one_time_keys, 5);
    assertEquals((await call("keys-upload", bob.token, { device_id: device.deviceId, one_time_keys: keys })).body.remaining_one_time_keys, 5);

    // Another user can list Bob's devices and claim; each claim returns a different key.
    const listed = await call("users-devices", alice.token, { user_id: bob.id });
    assertEquals(listed.body.master_key, master.publicKey);
    assertEquals(listed.body.devices.length, 1);
    assertEquals(listed.body.devices[0].identity_key, device.identityKey);

    const claimed = new Set<string>();
    for (let i = 0; i < 5; i++) {
      const claim = await call("keys-claim", alice.token, { user_id: bob.id });
      assertEquals(claim.status, 200);
      const k = claim.body.devices[0].one_time_key;
      assert(k, `claim ${i} should return a key`);
      assert(!claimed.has(k.key_id), "a key is claimed only once");
      claimed.add(k.key_id);
    }
    assertEquals(claimed.size, 5);
    const empty = await call("keys-claim", alice.token, { user_id: bob.id });
    assertEquals(empty.body.devices[0].one_time_key, null, "the pool is empty");
    // The count dropped to zero: topping up with one new key reports exactly 1.
    assertEquals((await call("keys-upload", bob.token, { device_id: device.deviceId, one_time_keys: otk(1, "z") })).body.remaining_one_time_keys, 1);

    // Registering the same device again is idempotent; another user cannot take its id.
    const again = await call("devices-register", bob.token, {
      device_id: device.deviceId, identity_key: device.identityKey, signing_key: device.signingKey,
      master_key: master.publicKey,
      master_signature: await master.sign(`lime-device-v1\n${device.deviceId}\n${device.identityKey}\n${device.signingKey}`),
    });
    assertEquals(again.status, 200);
    const other = await newMasterKey();
    const stolen = await call("devices-register", alice.token, {
      device_id: device.deviceId, identity_key: device.identityKey, signing_key: device.signingKey,
      master_key: other.publicKey,
      master_signature: await other.sign(`lime-device-v1\n${device.deviceId}\n${device.identityKey}\n${device.signingKey}`),
    });
    assertEquals(stolen.status, 409);
  });
});

Deno.test("sealed send needs no token and the right access key; an identified send records the sender", opts, async () => {
  await withUsers(2, async ([alice, bob]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const accessKey = await setAccessKey(bob);

    // Right key, NO Authorization header at all: accepted.
    const ok = await call("send", null, { ciphertext: ciphertext(), recipients: [{ to_device: device.deviceId, access: { sealed: accessKey } }] });
    assertEquals(ok.status, 200);
    assertEquals(ok.body.stored, 1);

    // A wrong key: 403, and nothing is stored.
    const wrong = await call("send", null, { ciphertext: ciphertext(), recipients: [{ to_device: device.deviceId, access: { sealed: toBase64(randomBytes(16)) } }] });
    assertEquals(wrong.status, 403);
    // A user with no access key set cannot be sent to sealed.
    const carolDevice = await registerDevice(alice, await newMasterKey());
    const noKey = await call("send", null, { ciphertext: ciphertext(), recipients: [{ to_device: carolDevice.deviceId, access: { sealed: accessKey } }] });
    assertEquals(noKey.status, 403);

    // An identified send needs a user token and records the sender.
    const noToken = await call("send", null, { ciphertext: ciphertext(), recipients: [{ to_device: device.deviceId, access: { identified: true } }] });
    assertEquals(noToken.status, 401);
    const identified = await call("send", alice.token, { ciphertext: ciphertext(), recipients: [{ to_device: device.deviceId, access: { identified: true } }] });
    assertEquals(identified.status, 200);

    const fetched = await fetchItems(bob, device.deviceId);
    assertEquals(fetched.status, 200);
    assertEquals(fetched.body.items.length, 2, "the wrong-key send stored nothing");
    const [sealed, stranger] = fetched.body.items;
    assertEquals(sealed.identified, undefined, "a sealed item carries no sender");
    assertEquals(sealed.sender_user, undefined);
    assertEquals(stranger.identified, true);
    assertEquals(stranger.sender_user, alice.id);

    // The database holds no sender for the sealed one.
    const { data } = await admin.from("mailbox_items").select("identified, sender_user").eq("to_device", device.deviceId).order("cursor");
    assertEquals(data, [{ identified: false, sender_user: null }, { identified: true, sender_user: alice.id }]);
  });
});

Deno.test("fan-out to 3 devices: each fetches only its own items", opts, async () => {
  await withUsers(3, async ([alice, bob, carol]) => {
    const master = await newMasterKey();
    const bobDevices = await Promise.all([registerDevice(bob, master), registerDevice(bob, master)]);
    const carolDevice = await registerDevice(carol, await newMasterKey());
    const bobKey = await setAccessKey(bob);
    const carolKey = await setAccessKey(carol);
    const payload = ciphertext(128);

    const res = await call("send", null, {
      ciphertext: payload,
      recipients: [
        { to_device: bobDevices[0].deviceId, access: { sealed: bobKey } },
        { to_device: bobDevices[1].deviceId, access: { sealed: bobKey } },
        { to_device: carolDevice.deviceId, access: { sealed: carolKey } },
      ],
    });
    assertEquals(res.status, 200);
    assertEquals(res.body.stored, 3);

    for (const [user, device] of [[bob, bobDevices[0]], [bob, bobDevices[1]], [carol, carolDevice]] as const) {
      const items = (await fetchItems(user, device.deviceId)).body.items;
      assertEquals(items.length, 1);
      assertEquals(items[0].ciphertext, payload);
    }
    // A device can only be read by its own user.
    assertEquals((await fetchItems(alice, bobDevices[0].deviceId)).status, 403);
    assertEquals((await fetchItems(bob, carolDevice.deviceId)).status, 403);
  });
});

Deno.test("ack deletes up to the cursor and nothing else", opts, async () => {
  await withUsers(1, async ([bob]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const key = await setAccessKey(bob);
    for (let i = 0; i < 3; i++) {
      await call("send", null, { ciphertext: ciphertext(32 + i), recipients: [{ to_device: device.deviceId, access: { sealed: key } }] });
    }
    const items = (await fetchItems(bob, device.deviceId)).body.items;
    assertEquals(items.length, 3);
    assert(items[0].cursor < items[1].cursor && items[1].cursor < items[2].cursor, "oldest first");

    const ack = await call("mailbox-ack", bob.token, { device_id: device.deviceId, up_to_cursor: items[1].cursor });
    assertEquals(ack.body.deleted, 2);
    const left = (await fetchItems(bob, device.deviceId)).body.items;
    assertEquals(left.length, 1);
    assertEquals(left[0].cursor, items[2].cursor);
    // `after` skips what was already seen.
    assertEquals((await fetchItems(bob, device.deviceId, items[2].cursor)).body.items.length, 0);
  });
});

Deno.test("de-duplication: the same ciphertext twice is one item per device", opts, async () => {
  await withUsers(1, async ([bob]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const key = await setAccessKey(bob);
    const same = ciphertext(80);
    const body = { ciphertext: same, recipients: [{ to_device: device.deviceId, access: { sealed: key } }] };
    assertEquals((await call("send", null, body)).body.stored, 1);
    const second = await call("send", null, body);
    assertEquals(second.body.stored, 0);
    assertEquals(second.body.duplicates, 1);
    assertEquals((await fetchItems(bob, device.deviceId)).body.items.length, 1);
    // A different ciphertext is a new item.
    await call("send", null, { ...body, ciphertext: ciphertext(80) });
    assertEquals((await fetchItems(bob, device.deviceId)).body.items.length, 2);
  });
});

Deno.test("the item size limit is 64 KB", opts, async () => {
  await withUsers(1, async ([bob]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const key = await setAccessKey(bob);
    const send = (size: number) => call("send", null, { ciphertext: ciphertext(size), recipients: [{ to_device: device.deviceId, access: { sealed: key } }] });
    assertEquals((await send(65536)).status, 200);
    const tooBig = await send(65537);
    assertEquals(tooBig.status, 413);
    assertEquals(tooBig.body.error, "too_large");
  });
});

Deno.test("rate limits trip: sends, claims and registrations", opts, async () => {
  await withUsers(3, async ([bob, claimer, registrant]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const key = await setAccessKey(bob);
    // 121 recipient-items in one minute for one access key is over the 120 limit.
    const recipients = Array.from({ length: 121 }, () => ({ to_device: device.deviceId, access: { sealed: key } }));
    const sends = await call("send", null, { ciphertext: ciphertext(), recipients });
    assertEquals(sends.status, 429);
    assertEquals(sends.body.error, "rate_limited");
    // The same key is now over its window: even one more item is refused until the minute passes.
    assertEquals((await call("send", null, { ciphertext: ciphertext(), recipients: recipients.slice(0, 1) })).status, 429);

    // 60 key claims per minute per user.
    for (let i = 0; i < 60; i++) assertEquals((await call("keys-claim", claimer.token, { user_id: bob.id })).status, 200);
    assertEquals((await call("keys-claim", claimer.token, { user_id: bob.id })).status, 429);

    // 10 registrations per hour per user.
    const master = await newMasterKey();
    for (let i = 0; i < 10; i++) await registerDevice(registrant, master);
    const eleventh = await call("devices-register", registrant.token, {
      device_id: crypto.randomUUID(), identity_key: toBase64(randomBytes(32)), signing_key: toBase64(randomBytes(32)),
      master_key: master.publicKey, master_signature: toBase64(randomBytes(64)),
    });
    assertEquals(eleventh.status, 429);
  });
});

Deno.test("RLS and grants: anon and authenticated can reach no table or function", opts, async () => {
  await withUsers(1, async ([bob]) => {
    const device = await registerDevice(bob, await newMasterKey());
    await setAccessKey(bob);
    await call("send", bob.token, { ciphertext: ciphertext(), recipients: [{ to_device: device.deviceId, access: { identified: true } }] });

    const anon = createClient(API_URL, ANON_KEY, { auth: { persistSession: false } });
    const signedIn = createClient(API_URL, ANON_KEY, {
      auth: { persistSession: false }, global: { headers: { authorization: `Bearer ${bob.token}` } },
    });
    for (const [label, client] of [["anon", anon], ["authenticated", signedIn]] as const) {
      for (const table of TABLES) {
        const { data, error } = await client.from(table).select("*").limit(1);
        assert(error !== null || (data ?? []).length === 0, `${label} must not read ${table}`);
        assert(error !== null, `${label} should be refused outright on ${table}`);
        const insert = await client.from(table).insert({});
        assert(insert.error !== null, `${label} must not write ${table}`);
      }
      assert((await client.rpc("expire_mailbox_items", { p_days: 0 })).error !== null, `${label} must not call expire_mailbox_items`);
      assert((await client.rpc("take_rate_limit", { p_bucket: "x", p_cost: 1, p_limit: 1, p_window_seconds: 60 })).error !== null);
    }

    if (DB_URL) {
      const sql = postgres(DB_URL, { max: 1 });
      try {
        const grants = await sql`
          select grantee, table_name, privilege_type from information_schema.role_table_grants
          where table_schema = 'public' and grantee in ('anon', 'authenticated', 'PUBLIC') and table_name = any(${TABLES})`;
        assertEquals(grants.length, 0, `no table grants for anon/authenticated: ${JSON.stringify(grants)}`);
        const rls = await sql`
          select relname, relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'public' and relname = any(${TABLES})`;
        assertEquals(rls.length, TABLES.length);
        for (const row of rls) assert(row.relrowsecurity, `RLS is on for ${row.relname}`);
        const serviceGrants = await sql`
          select distinct table_name from information_schema.role_table_grants
          where table_schema = 'public' and grantee = 'service_role' and table_name = any(${TABLES})`;
        assertEquals(serviceGrants.length, TABLES.length, "service_role is granted every table");
      } finally {
        await sql.end();
      }
    }
  });
});

Deno.test("expiry: items older than 30 days are deleted, newer ones stay, and the cron job exists", opts, async () => {
  await withUsers(1, async ([bob]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const key = await setAccessKey(bob);
    const send = () => call("send", null, { ciphertext: ciphertext(), recipients: [{ to_device: device.deviceId, access: { sealed: key } }] });
    await send();
    await send();
    const items = (await fetchItems(bob, device.deviceId)).body.items;
    assertEquals(items.length, 2);

    const old = new Date(Date.now() - 31 * 24 * 3600 * 1000).toISOString();
    const fresh = new Date(Date.now() - 29 * 24 * 3600 * 1000).toISOString();
    await admin.from("mailbox_items").update({ received_at: old }).eq("cursor", items[0].cursor);
    await admin.from("mailbox_items").update({ received_at: fresh }).eq("cursor", items[1].cursor);

    const { data: removed, error } = await admin.rpc("expire_mailbox_items");
    assertEquals(error, null);
    assert(Number(removed) >= 1);
    const left = (await fetchItems(bob, device.deviceId)).body.items;
    assertEquals(left.length, 1);
    assertEquals(left[0].cursor, items[1].cursor);
  });

  if (DB_URL) {
    const sql = postgres(DB_URL, { max: 1 });
    try {
      const jobs = await sql`select schedule, command from cron.job where jobname = 'lime-expire-mailbox'`;
      assertEquals(jobs.length, 1, "the daily expiry job is scheduled");
      assertEquals(jobs[0].schedule, "17 3 * * *");
      assert(String(jobs[0].command).includes("expire_mailbox_items(30)"));
    } finally {
      await sql.end();
    }
  }
});

Deno.test("a revoked device can neither fetch nor be sent to", opts, async () => {
  await withUsers(1, async ([bob]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const key = await setAccessKey(bob);
    assertEquals((await fetchItems(bob, device.deviceId)).status, 200);
    await admin.from("devices").update({ revoked_at: new Date().toISOString() }).eq("device_id", device.deviceId);
    assertEquals((await fetchItems(bob, device.deviceId)).status, 403);
    assertEquals((await call("mailbox-ack", bob.token, { device_id: device.deviceId, up_to_cursor: 1 })).status, 403);
    assertEquals((await call("send", null, { ciphertext: ciphertext(), recipients: [{ to_device: device.deviceId, access: { sealed: key } }] })).status, 403);
    assertEquals((await call("users-devices", bob.token, { user_id: bob.id })).body.devices.length, 0, "a revoked device is not listed");
  });
});

Deno.test("a send nudges the device's Realtime channel with no content", opts, async () => {
  await withUsers(1, async ([bob]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const key = await setAccessKey(bob);
    const client = createClient(API_URL, ANON_KEY, { auth: { persistSession: false } });
    const received = new Promise<unknown>((resolve) => {
      const timer = setTimeout(() => resolve(null), 8000);
      const channel = client.channel(`device:${device.deviceId}`);
      channel.on("broadcast", { event: "new" }, (message: unknown) => { clearTimeout(timer); resolve(message); })
        .subscribe(async (status: string) => {
          if (status === "SUBSCRIBED") {
            await call("send", null, { ciphertext: ciphertext(), recipients: [{ to_device: device.deviceId, access: { sealed: key } }] });
          }
        });
    });
    const message = await received as { payload?: { type?: string } } | null;
    await client.removeAllChannels();
    assertNotEquals(message, null, "a nudge arrived");
    assertEquals(message?.payload, { type: "new" }, "the nudge carries no content");
  });
});
