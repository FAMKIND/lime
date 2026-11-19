// LIME-342a: the 5-device limit and unlinking a computer, against the LOCAL Supabase stack. Run with ./supabase/test.sh.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { call, deleteUser, newMasterKey, newUser, otk, registerDevice, type MasterKey, type TestUser } from "./helpers.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };

async function withUser<T>(fn: (user: TestUser) => Promise<T>): Promise<T> {
  const user = await newUser();
  try {
    return await fn(user);
  } finally {
    await deleteUser(user);
  }
}

async function revoke(user: TestUser, master: MasterKey, target: string, from: string, over: { at?: number; kind?: string; signText?: string } = {}) {
  const at = over.at ?? Date.now();
  const kind = over.kind ?? "computer";
  const signature = await master.sign(over.signText ?? `lime-revoke-v1\n${user.id}\n${target}\n${at}\n${kind}`);
  return await call("devices-revoke", user.token, { device_id: target, from_device: from, at, kind, master_signature: signature });
}

Deno.test("a sixth active device is refused (409 too_many_devices); a known device registering again is not a new one", opts, async () => {
  await withUser(async (user) => {
    const master = await newMasterKey();
    const devices = [];
    for (let i = 0; i < 5; i++) devices.push(await registerDevice(user, master));
    // The same device again (idempotent) is fine.
    const again = await call("devices-register", user.token, {
      device_id: devices[0].deviceId, identity_key: devices[0].identityKey, signing_key: devices[0].signingKey, master_key: master.publicKey,
      master_signature: await master.sign(`lime-device-v1\n${devices[0].deviceId}\n${devices[0].identityKey}\n${devices[0].signingKey}`),
    });
    assertEquals(again.status, 200);
    // A sixth new one is not.
    const sixth = { deviceId: crypto.randomUUID(), identityKey: btoa("i".repeat(32)), signingKey: btoa("s".repeat(32)) };
    const refused = await call("devices-register", user.token, {
      device_id: sixth.deviceId, identity_key: sixth.identityKey, signing_key: sixth.signingKey, master_key: master.publicKey,
      master_signature: await master.sign(`lime-device-v1\n${sixth.deviceId}\n${sixth.identityKey}\n${sixth.signingKey}`),
    });
    assertEquals(refused.status, 409);
    assertEquals(refused.body.error, "too_many_devices");
    // After one is unlinked there is room again.
    { const r = await revoke(user, master, devices[4].deviceId, devices[0].deviceId); assertEquals(r.status, 200, JSON.stringify(r.body)); }
    const room = await call("devices-register", user.token, {
      device_id: sixth.deviceId, identity_key: sixth.identityKey, signing_key: sixth.signingKey, master_key: master.publicKey,
      master_signature: await master.sign(`lime-device-v1\n${sixth.deviceId}\n${sixth.identityKey}\n${sixth.signingKey}`),
    });
    assertEquals(room.status, 201);
  });
});

Deno.test("unlinking: a good signature revokes (its mail and keys go, it is unlisted, every function says 401 revoked); the refusals", opts, async () => {
  await withUser(async (user) => {
    const master = await newMasterKey();
    const phone = await registerDevice(user, master);
    const computer = await registerDevice(user, master);
    await call("keys-upload", user.token, { device_id: computer.deviceId, one_time_keys: otk(3) });

    // Refused: a bad signature, a stale one, one for another device, "not a computer", the caller's own device, a stranger's device id.
    assertEquals((await revoke(user, master, computer.deviceId, phone.deviceId, { signText: "lime-revoke-v1\nnot\nthe\nright\ncomputer" })).body.error, "bad_signature");
    assertEquals((await revoke(user, master, computer.deviceId, phone.deviceId, { at: Date.now() - 10 * 60 * 1000 })).body.error, "stale");
    const other = await newMasterKey();
    assertEquals((await revoke(user, other, computer.deviceId, phone.deviceId)).body.error, "bad_signature", "another key's signature");
    const phoneKind = await revoke(user, master, computer.deviceId, phone.deviceId, { kind: "phone" });
    assertEquals(phoneKind.status, 400, "a phone or tablet is not unlinked");
    const own = await revoke(user, master, phone.deviceId, phone.deviceId);
    assertEquals(own.status, 400, "a device cannot unlink itself");
    assertEquals((await revoke(user, master, crypto.randomUUID(), phone.deviceId)).status, 404, "an unknown device");
    // Nothing happened yet.
    assertEquals((await call("mailbox-fetch", user.token, { device_id: computer.deviceId, after: 0 })).status, 200);

    // A good one.
    const done = await revoke(user, master, computer.deviceId, phone.deviceId);
    assertEquals(done.status, 200);
    assertEquals(done.body.revoked, true);
    // The revoked device is told so (401 revoked) on its next call; the phone is not affected.
    const fetched = await call("mailbox-fetch", user.token, { device_id: computer.deviceId, after: 0 });
    assertEquals(fetched.status, 401);
    assertEquals(fetched.body.error, "revoked");
    assertEquals((await call("keys-upload", user.token, { device_id: computer.deviceId, one_time_keys: otk(1) })).status, 401);
    assertEquals((await call("mailbox-fetch", user.token, { device_id: phone.deviceId, after: 0 })).status, 200);
    // Unlisted; and unlinking twice says not found.
    const listed = await call("users-devices", user.token, { user_id: user.id });
    assertEquals(listed.body.devices.map((d: { device_id: string }) => d.device_id), [phone.deviceId]);
    assertEquals((await revoke(user, master, computer.deviceId, phone.deviceId)).status, 404);
  });
});

Deno.test("another account's device cannot be unlinked, and a revoked device cannot unlink", opts, async () => {
  await withUser(async (alice) => {
    await withUser(async (bob) => {
      const aliceMaster = await newMasterKey();
      const bobMaster = await newMasterKey();
      const a1 = await registerDevice(alice, aliceMaster);
      const a2 = await registerDevice(alice, aliceMaster);
      const b1 = await registerDevice(bob, bobMaster);
      // Alice signs for Bob's device: not found for her account (she cannot touch it).
      assertEquals((await revoke(alice, aliceMaster, b1.deviceId, a1.deviceId)).status, 404);
      // A revoked device cannot be the caller.
      assertEquals((await revoke(alice, aliceMaster, a2.deviceId, a1.deviceId)).status, 200);
      const third = await registerDevice(alice, aliceMaster);
      const fromRevoked = await revoke(alice, aliceMaster, third.deviceId, a2.deviceId);
      assertEquals(fromRevoked.status, 401);
      assert(fromRevoked.body.error === "revoked");
    });
  });
});
