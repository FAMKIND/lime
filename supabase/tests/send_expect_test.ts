// LIME-120: `send` with `expect` (the sender's cached view of the recipient's devices) and the narrower `keys-claim`.
// Throwaway users on the LOCAL stack only. Run with ./supabase/test.sh.

import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  admin, call, ciphertext, deleteUser, newMasterKey, newUser, otk, registerDevice, setAccessKey, type MasterKey, type TestUser,
} from "./helpers.ts";
import { sha256, toHex } from "../functions/_shared/bytes.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };

async function withUsers<T>(count: number, fn: (users: TestUser[]) => Promise<T>): Promise<T> {
  const users = await Promise.all(Array.from({ length: count }, newUser));
  try {
    return await fn(users);
  } finally {
    await Promise.all(users.map(deleteUser));
  }
}

const masterHash = async (master: MasterKey) => toHex(await sha256(new TextEncoder().encode(master.publicKey)));
const sealed = (device: string, key: string) => [{ to_device: device, access: { sealed: key } }];
const mailboxCount = async (device: string) => (await admin.from("mailbox_items").select("cursor").eq("to_device", device)).data?.length ?? 0;

Deno.test("send with a matching expect is stored and says it was checked; without expect nothing changes", opts, async () => {
  await withUsers(2, async ([alice, bob]) => {
    const master = await newMasterKey();
    const device = await registerDevice(bob, master);
    const key = await setAccessKey(bob);
    const expect = { [bob.id]: { devices: [device.deviceId], master: await masterHash(master) } };

    const ok = await call("send", null, { ciphertext: ciphertext(), recipients: sealed(device.deviceId, key), expect });
    assertEquals(ok.status, 200);
    assertEquals(ok.body.checked, true);
    assertEquals(ok.body.stored, 1);

    const old = await call("send", null, { ciphertext: ciphertext(), recipients: sealed(device.deviceId, key) });
    assertEquals(old.status, 200);
    assertEquals(old.body.checked, false, "an old client's send is not checked, and not refused");

    // Identified, with expect, also works.
    const identified = await call("send", alice.token, { ciphertext: ciphertext(), recipients: [{ to_device: device.deviceId, access: { identified: true } }], expect });
    assertEquals(identified.status, 200);
    assertEquals(identified.body.checked, true);
    assertEquals(await mailboxCount(device.deviceId), 3);
  });
});

Deno.test("a new device (or a changed master key) is a 409 with the current list, and nothing is stored", opts, async () => {
  await withUsers(2, async ([_alice, bob]) => {
    const master = await newMasterKey();
    const first = await registerDevice(bob, master);
    const key = await setAccessKey(bob);
    const expect = { [bob.id]: { devices: [first.deviceId], master: await masterHash(master) } };
    const second = await registerDevice(bob, master);   // a linked device: the same master key

    const stale = await call("send", null, { ciphertext: ciphertext(), recipients: sealed(first.deviceId, key), expect });
    assertEquals(stale.status, 409);
    assertEquals(stale.body.error, "devices_changed");
    assertEquals(stale.body.stale.length, 1);
    const entry = stale.body.stale[0];
    assertEquals(entry.user_id, bob.id);
    assertEquals(entry.master_key, master.publicKey);
    assertEquals(entry.missing, [second.deviceId]);
    assertEquals(entry.extra, []);
    assertEquals(entry.devices.map((d: { device_id: string }) => d.device_id).sort(), [first.deviceId, second.deviceId].sort());
    assert(entry.devices.every((d: { identity_key: string; signing_key: string; master_signature: string }) => d.identity_key && d.signing_key && d.master_signature), "the list is complete enough to verify");
    assertEquals(await mailboxCount(first.deviceId), 0, "nothing was stored");

    // With the list the 409 gave, the retry goes through.
    const fresh = { [bob.id]: { devices: [first.deviceId, second.deviceId], master: await masterHash(master) } };
    const retry = await call("send", null, { ciphertext: ciphertext(), recipients: sealed(first.deviceId, key), expect: fresh });
    assertEquals(retry.status, 200);

    // A changed master key is also stale, even with the same device ids.
    const wrongMaster = { [bob.id]: { devices: [first.deviceId, second.deviceId], master: "00".repeat(32) } };
    const changed = await call("send", null, { ciphertext: ciphertext(), recipients: sealed(first.deviceId, key), expect: wrongMaster });
    assertEquals(changed.status, 409);
    assertEquals(changed.body.stale[0].master_changed, true);
  });
});

Deno.test("a revoked device is a 410 for someone who holds the access key; the key is checked first", opts, async () => {
  await withUsers(2, async ([_alice, bob]) => {
    const master = await newMasterKey();
    const old = await registerDevice(bob, master);
    const key = await setAccessKey(bob);
    const expect = { [bob.id]: { devices: [old.deviceId], master: await masterHash(master) } };
    await admin.from("devices").update({ revoked_at: new Date().toISOString() }).eq("device_id", old.deviceId);

    const gone = await call("send", null, { ciphertext: ciphertext(), recipients: sealed(old.deviceId, key), expect });
    assertEquals(gone.status, 410);
    assertEquals(gone.body.error, "devices_revoked");
    assertEquals(gone.body.revoked, [old.deviceId]);
    assertEquals(gone.body.stale[0].extra, [old.deviceId]);
    assertEquals(gone.body.stale[0].devices, [], "no live device is left");

    // Not a holder of the key: the same 403 as for any wrong key. Nothing about the revocation leaks.
    const stranger = await call("send", null, { ciphertext: ciphertext(), recipients: sealed(old.deviceId, "AAAAAAAAAAAAAAAAAAAAAA=="), expect });
    assertEquals(stranger.status, 403);

    // Without expect a revoked device is refused as before (403 sealed; 404 identified).
    assertEquals((await call("send", null, { ciphertext: ciphertext(), recipients: sealed(old.deviceId, key) })).status, 403);
    assertEquals(await mailboxCount(old.deviceId), 0);
  });
});

Deno.test("a bad expect is a 400 and an expect for someone else's devices never reveals them to a wrong key", opts, async () => {
  await withUsers(2, async ([_alice, bob]) => {
    const master = await newMasterKey();
    const device = await registerDevice(bob, master);
    const key = await setAccessKey(bob);
    const bad = await call("send", null, { ciphertext: ciphertext(), recipients: sealed(device.deviceId, key), expect: { nope: 1 } });
    assertEquals(bad.status, 400);
    const empty = await call("send", null, { ciphertext: ciphertext(), recipients: sealed(device.deviceId, key), expect: {} });
    assertEquals(empty.status, 400);
    // A wrong access key gets 403 whatever expect says (the 409 body is only for a holder of the key).
    const wrongKey = await call("send", null, {
      ciphertext: ciphertext(), recipients: sealed(device.deviceId, "AAAAAAAAAAAAAAAAAAAAAA=="),
      expect: { [bob.id]: { devices: [], master: "00" } },
    });
    assertEquals(wrongKey.status, 403);
  });
});

Deno.test("keys-claim with device_ids claims only those devices; without it, all (as before)", opts, async () => {
  await withUsers(2, async ([alice, bob]) => {
    const master = await newMasterKey();
    const d1 = await registerDevice(bob, master);
    const d2 = await registerDevice(bob, master);
    for (const d of [d1, d2]) {
      const up = await call("keys-upload", bob.token, { device_id: d.deviceId, one_time_keys: otk(3, d.deviceId.slice(0, 4)) });
      assertEquals(up.status, 200);
    }
    const remaining = async (id: string) => (await admin.from("one_time_keys").select("id").eq("device_id", id).is("claimed_at", null)).data?.length ?? 0;

    const some = await call("keys-claim", alice.token, { user_id: bob.id, device_ids: [d2.deviceId] });
    assertEquals(some.status, 200);
    const byDevice = new Map(some.body.devices.map((d: { device_id: string; one_time_key: unknown }) => [d.device_id, d.one_time_key]));
    assert(byDevice.get(d2.deviceId), "the asked-for device gave a key");
    assertEquals(byDevice.get(d1.deviceId), null, "the other device's key was not taken");
    assertEquals(await remaining(d1.deviceId), 3);
    assertEquals(await remaining(d2.deviceId), 2);

    const all = await call("keys-claim", alice.token, { user_id: bob.id });
    assertEquals(all.status, 200);
    assertEquals(await remaining(d1.deviceId), 2, "without device_ids every active device is claimed, as before");
    assertEquals(await remaining(d2.deviceId), 1);

    assertEquals((await call("keys-claim", alice.token, { user_id: bob.id, device_ids: [] })).status, 400);
    assertEquals((await call("keys-claim", alice.token, { user_id: bob.id, device_ids: ["x"] })).status, 400);
  });
});
