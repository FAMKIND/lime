// LIME-139: signed access. A sealed send carries an Ed25519 signature over the ciphertext and the recipient device, valid for that message
// to that device only. Run with ./supabase/test.sh.

import { assertEquals } from "jsr:@std/assert@1";
import { call, ciphertext, deleteUser, newMasterKey, newUser, randomBytes, registerDevice, setHashOnlyAccessKey, setSignedAccess, type TestUser } from "./helpers.ts";
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
      await setHashOnlyAccessKey(dave);
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

Deno.test("the removed sealed (access key) proof is refused with the same opaque 403, alone or inside a batch (LIME-166, F-02)", opts, async () => {
  await withUsers(2, async ([bob, carol]) => {
    const bobDevice = await registerDevice(bob, await newMasterKey());
    const carolDevice = await registerDevice(carol, await newMasterKey());
    const { signer, accessKey: bobKey } = await setSignedAccess(bob); // Bob has both a public key and an access-key hash on file
    const carolKey = await setHashOnlyAccessKey(carol);
    const ct = ciphertext();

    // The right access key, which used to be accepted, is now refused: for a user who has signed access too, and for one with only the hash.
    assertEquals((await sendTo([{ to_device: bobDevice.deviceId, access: { sealed: bobKey } }], ct)).status, 403, "the access key is not a proof any more");
    assertEquals((await sendTo([{ to_device: carolDevice.deviceId, access: { sealed: carolKey } }], ct)).status, 403);
    const refused = await sendTo([{ to_device: bobDevice.deviceId, access: { sealed: bobKey } }], ct);
    assertEquals(refused.body.error, "access_denied", "the same opaque answer as any wrong proof");

    // A batch with one removed-style proof stores nothing for anyone (all or nothing), even if the other recipient's signature is right.
    const ct2 = ciphertext(100);
    const mixed = await sendTo([
      { to_device: bobDevice.deviceId, access: { signed: await signer.sign(ct2, bobDevice.deviceId) } },
      { to_device: carolDevice.deviceId, access: { sealed: carolKey } },
    ], ct2);
    assertEquals(mixed.status, 403);
    const signedOnly = await sendTo([{ to_device: bobDevice.deviceId, access: { signed: await signer.sign(ct2, bobDevice.deviceId) } }], ct2);
    assertEquals(signedOnly.status, 200);
    assertEquals(signedOnly.body.stored, 1, "nothing was stored by the refused batch, so this is the first copy");
  });
});

Deno.test("a rotation without a public key clears the old one, and a bad public key is refused", opts, async () => {
  await withUsers(1, async ([bob]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const { signer } = await setSignedAccess(bob);
    const ct = ciphertext();
    assertEquals((await sendTo([{ to_device: device.deviceId, access: { signed: await signer.sign(ct, device.deviceId) } }], ct)).status, 200);

    // An older build rotates the key (a block): hash only. The previous delivery key's public key must not survive.
    await setHashOnlyAccessKey(bob);
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
