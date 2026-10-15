// LIME-139: signed access. A sealed send carries an Ed25519 signature over the ciphertext and the recipient device, valid for that message
// to that device only. Run with ./supabase/test.sh.

import { assertEquals } from "jsr:@std/assert@1";
import { call, ciphertext, deleteUser, newMasterKey, newUser, randomBytes, registerDevice, setAccessKey, setSignedAccess, type TestUser } from "./helpers.ts";
import { toBase64 } from "../functions/_shared/bytes.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };

async function withUsers<T>(count: number, fn: (users: TestUser[]) => Promise<T>): Promise<T> {
  const users = await Promise.all(Array.from({ length: count }, newUser));
  try {
    return await fn(users);
  } finally {
    await Promise.all(users.map(deleteUser));
  }
}

const sendTo = (recipients: unknown[], ct: string) => call("send", null, { ciphertext: ct, recipients });

Deno.test("a valid signature is accepted with no token, and it is only good for that ciphertext and that device", opts, async () => {
  await withUsers(1, async ([bob]) => {
    const master = await newMasterKey();
    const first = await registerDevice(bob, master);
    const second = await registerDevice(bob, master);
    const { signer } = await setSignedAccess(bob);
    const ct = ciphertext();

    const ok = await sendTo([{ to_device: first.deviceId, access: { signed: await signer.sign(ct, first.deviceId) } }], ct);
    assertEquals(ok.status, 200);
    assertEquals(ok.body.stored, 1);

    // The same signature on a different ciphertext: refused (a relay cannot reuse it for another message).
    const other = ciphertext(80);
    const replay = await sendTo([{ to_device: first.deviceId, access: { signed: await signer.sign(ct, first.deviceId) } }], other);
    assertEquals(replay.status, 403);
    // The same signature for another device of the same person: refused.
    const elsewhere = await sendTo([{ to_device: second.deviceId, access: { signed: await signer.sign(ct, first.deviceId) } }], ct);
    assertEquals(elsewhere.status, 403);
    // A signature made for that device and ciphertext is fine for the second device.
    const secondOk = await sendTo([{ to_device: second.deviceId, access: { signed: await signer.sign(ct, second.deviceId) } }], ct);
    assertEquals(secondOk.status, 200);
  });
});

Deno.test("a signature from another key, a short or garbled one, or no public key on file is 403 (like a wrong key)", opts, async () => {
  await withUsers(2, async ([bob, carol]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const { signer } = await setSignedAccess(bob);
    const ct = ciphertext();
    const mine = { to_device: device.deviceId };

    const { signer: stranger } = await setSignedAccess(carol);
    assertEquals((await sendTo([{ ...mine, access: { signed: await stranger.sign(ct, device.deviceId) } }], ct)).status, 403, "someone else's key");
    const good = await signer.sign(ct, device.deviceId);
    assertEquals((await sendTo([{ ...mine, access: { signed: good.slice(0, 40) } }], ct)).status, 403, "too short");
    assertEquals((await sendTo([{ ...mine, access: { signed: "not base64 !!" } }], ct)).status, 403, "not base64");
    assertEquals((await sendTo([{ ...mine, access: { signed: 7 } }], ct)).status, 403, "not text");
    assertEquals((await sendTo([{ ...mine, access: {} }], ct)).status, 403, "no proof at all");

    // A user who only has the old access key set (no public key on file) cannot be sent to signed.
    const dave = await newUser();
    try {
      const daveDevice = await registerDevice(dave, await newMasterKey());
      await setAccessKey(dave);
      assertEquals((await sendTo([{ to_device: daveDevice.deviceId, access: { signed: await signer.sign(ct, daveDevice.deviceId) } }], ct)).status, 403, "no public key on file");
    } finally {
      await deleteUser(dave);
    }
    // And a user who set nothing at all.
    const eve = await newUser();
    try {
      const eveDevice = await registerDevice(eve, await newMasterKey());
      assertEquals((await sendTo([{ to_device: eveDevice.deviceId, access: { signed: await signer.sign(ct, eveDevice.deviceId) } }], ct)).status, 403);
    } finally {
      await deleteUser(eve);
    }
  });
});

Deno.test("the older sealed (access key) path still works during the overlap, and one batch can mix both", opts, async () => {
  await withUsers(2, async ([bob, carol]) => {
    const bobDevice = await registerDevice(bob, await newMasterKey());
    const carolDevice = await registerDevice(carol, await newMasterKey());
    const { signer, accessKey: bobKey } = await setSignedAccess(bob); // Bob's build is new and still sets the hash too
    const carolKey = await setAccessKey(carol); // Carol's is an older build: hash only
    const ct = ciphertext();

    assertEquals((await sendTo([{ to_device: bobDevice.deviceId, access: { sealed: bobKey } }], ct)).status, 200, "the old key still works for Bob");
    const mixed = await sendTo([
      { to_device: bobDevice.deviceId, access: { signed: await signer.sign(ct, bobDevice.deviceId) } },
      { to_device: carolDevice.deviceId, access: { sealed: carolKey } },
    ], ciphertext(90));
    assertEquals(mixed.status, 403, "(the first ciphertext differs from the one signed, so this whole batch is refused)");
    const ct2 = ciphertext(100);
    const ok = await sendTo([
      { to_device: bobDevice.deviceId, access: { signed: await signer.sign(ct2, bobDevice.deviceId) } },
      { to_device: carolDevice.deviceId, access: { sealed: carolKey } },
    ], ct2);
    assertEquals(ok.status, 200);
    assertEquals(ok.body.stored, 2, "one signed and one sealed recipient in the same batch");

    // All or nothing: one bad proof in a batch stores nothing for anyone.
    const ct3 = ciphertext(110);
    const bad = await sendTo([
      { to_device: bobDevice.deviceId, access: { signed: await signer.sign(ct3, bobDevice.deviceId) } },
      { to_device: carolDevice.deviceId, access: { sealed: toBase64(randomBytes(16)) } },
    ], ct3);
    assertEquals(bad.status, 403);
  });
});

Deno.test("a rotation without a public key clears the old one, and a bad public key is refused", opts, async () => {
  await withUsers(1, async ([bob]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const { signer } = await setSignedAccess(bob);
    const ct = ciphertext();
    assertEquals((await sendTo([{ to_device: device.deviceId, access: { signed: await signer.sign(ct, device.deviceId) } }], ct)).status, 200);

    // An older build rotates the key (a block): hash only. The previous delivery key's public key must not survive.
    await setAccessKey(bob);
    const ct2 = ciphertext(70);
    assertEquals((await sendTo([{ to_device: device.deviceId, access: { signed: await signer.sign(ct2, device.deviceId) } }], ct2)).status, 403, "the public key is cleared");

    const short = await call("delivery-access-set", bob.token, { access_key_hash: toBase64(randomBytes(32)), access_public_key: toBase64(randomBytes(31)) });
    assertEquals(short.status, 400);
    const garbled = await call("delivery-access-set", bob.token, { access_key_hash: toBase64(randomBytes(32)), access_public_key: "###" });
    assertEquals(garbled.status, 400);
  });
});

Deno.test("with expect, a signed send is checked first and a revoked device is only reported to a valid signer", opts, async () => {
  await withUsers(1, async ([bob]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const { signer } = await setSignedAccess(bob);
    const ct = ciphertext();
    const proof = await signer.sign(ct, device.deviceId);
    const body = { ciphertext: ct, recipients: [{ to_device: device.deviceId, access: { signed: proof } }], expect: { [bob.id]: { devices: [device.deviceId], master: "" } } };
    // A valid signer with an out-of-date view learns about the change (409), a wrong signer only gets 403.
    const checked = await call("send", null, body);
    assertEquals(checked.status, 409);
    const wrong = await call("send", null, { ...body, recipients: [{ to_device: device.deviceId, access: { signed: toBase64(randomBytes(64)) } }] });
    assertEquals(wrong.status, 403);
  });
});
