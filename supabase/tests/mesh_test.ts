// LIME-140: the mesh. The sealed routing header (opened here with the local test key) and `mesh-drop` against the local stack.
// Run with ./supabase/test.sh. The header cases need no stack.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { admin, call, deleteUser, newMasterKey, newUser, registerDevice, setAccessKey, setSignedAccess, type TestUser } from "./helpers.ts";
import { fromBase64, fromHex, sha256, toBase64 } from "../functions/_shared/bytes.ts";
import { openRoutingHeader, routingKeysFromEnv } from "../functions/_shared/mesh.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };

// The local stack's mesh key pair (supabase/config.toml: local test only, never staging).
const LOCAL_SECRET = "KILKJyNyeB2broEOGIiyuqZcUVWs9jZM9XtAjY/ZiWA=";
const LOCAL_PUBLIC = "GyNOPj7N/ovXno/OznB9bEtKB2PTAsuRK1XzXrzX7lY=";
const keys = new Map([[1, LOCAL_SECRET]]);

// What lime_core's test `the_sealed_header_vector_is_pinned_so_the_server_opens_what_the_phone_seals` seals with a fixed ephemeral key.
const RUST_VECTOR =
  "01132c442be010fbd57e72603328aa76e71fccc1503aae219327d14d9c9993f472aee31ccaa5d57330a036e255668651f607457eb3c4d50adf5eb4f2d56bceab33eee96e43f6301e10630620522a76be501696669c3e6a6deb2e7f9cfb4ecb69710a6744f256dec44f6e45a58db8b0ea849a20b3ad00208d4b6cdb3dbb262ee0c328e852";

const PKCS8_X25519 = Uint8Array.from([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20]);

/** The phone's side in TypeScript (the same construction as lime_core's `seal_header`), for crafting packets in the stack tests. */
async function sealHeader(serverPublicB64: string, keyId: number, toDevice: string, signed: string): Promise<Uint8Array> {
  const pair = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"]) as CryptoKeyPair;
  const ephemeral = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
  const server = await crypto.subtle.importKey("raw", fromBase64(serverPublicB64) as BufferSource, { name: "X25519" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "X25519", public: server }, pair.privateKey, 256));
  const hkdf = await crypto.subtle.importKey("raw", shared as BufferSource, "HKDF", false, ["deriveBits"]);
  const info = new Uint8Array([...new TextEncoder().encode("lime-mesh-header-v1"), keyId, ...ephemeral]);
  const okm = new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: info as BufferSource }, hkdf, 44 * 8));
  const aes = await crypto.subtle.importKey("raw", okm.slice(0, 32) as BufferSource, "AES-GCM", false, ["encrypt"]);
  const aad = new Uint8Array([keyId, ...ephemeral]);
  const plaintext = new TextEncoder().encode(JSON.stringify({ to_device: toDevice, access: { signed } }));
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: okm.slice(32, 44) as BufferSource, additionalData: aad as BufferSource }, aes, plaintext as BufferSource));
  return new Uint8Array([...aad, ...sealed]);
}

Deno.test("the server opens the header lime_core sealed (the pinned cross-language vector)", async () => {
  const opened = await openRoutingHeader(keys, fromHex(RUST_VECTOR));
  assert(opened, "it opens with the local secret");
  assertEquals(JSON.parse(new TextDecoder().decode(opened)), { to_device: "0a0b0c0d-0e0f-4a1b-8c2d-3e4f5a6b7c8d", access: { signed: "c2lnbmVk" } });
});

Deno.test("a header that was changed, cut, addressed to another key id or sealed to another server does not open", async () => {
  const good = fromHex(RUST_VECTOR);
  for (let i of [0, 1, 20, 33, 40, good.length - 1]) {
    const bad = good.slice();
    bad[i] ^= 1;
    assertEquals(await openRoutingHeader(keys, bad), null, `byte ${i} changed`);
  }
  assertEquals(await openRoutingHeader(keys, good.slice(0, good.length - 1)), null, "cut short");
  assertEquals(await openRoutingHeader(keys, good.slice(0, 20)), null, "far too short");
  assertEquals(await openRoutingHeader(new Map([[2, LOCAL_SECRET]]), good), null, "no key with that id");
  const other = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"]) as CryptoKeyPair;
  const otherPublic = toBase64(new Uint8Array(await crypto.subtle.exportKey("raw", other.publicKey)));
  const sealedToOther = await sealHeader(otherPublic, 1, crypto.randomUUID(), "c2ln");
  assertEquals(await openRoutingHeader(keys, sealedToOther), null, "sealed to another server's key");
  const mine = await sealHeader(LOCAL_PUBLIC, 1, "0a0b0c0d-0e0f-4a1b-8c2d-3e4f5a6b7c8d", "c2ln");
  assert(await openRoutingHeader(keys, mine), "this file's own sealer agrees with the server");
});

Deno.test("without the secret the server has no keys (mesh-drop answers 503 not_configured)", () => {
  const before = Deno.env.get("MESH_ROUTING_SECRET_KEY");
  Deno.env.delete("MESH_ROUTING_SECRET_KEY");
  try {
    assertEquals(routingKeysFromEnv().size, 0);
  } finally {
    if (before) Deno.env.set("MESH_ROUTING_SECRET_KEY", before);
  }
});

async function withUsers<T>(count: number, fn: (users: TestUser[]) => Promise<T>): Promise<T> {
  const users = await Promise.all(Array.from({ length: count }, newUser));
  try {
    return await fn(users);
  } finally {
    await Promise.all(users.map(deleteUser));
  }
}

const payloadOf = (n: number) => toBase64(new Uint8Array(100).fill(n));

Deno.test("mesh-drop: a relay uploads a sealed packet, the server stores it for the recipient device with no sender, and a repeat is a duplicate", opts, async () => {
  await withUsers(2, async ([relay, bob]) => {
    const device = await registerDevice(bob, await newMasterKey());
    const { signer } = await setSignedAccess(bob);
    const payload = payloadOf(1);
    const header = toBase64(await sealHeader(LOCAL_PUBLIC, 1, device.deviceId, await signer.sign(payload, device.deviceId)));

    const noSession = await call("mesh-drop", null, { header, payload });
    assertEquals(noSession.status, 401, "a signed-in session is required");
    const ok = await call("mesh-drop", relay.token, { header, payload });
    assertEquals(ok.status, 200);
    assertEquals(ok.body, { stored: 1, duplicates: 0 });
    const { data } = await admin.from("mailbox_items").select("identified, sender_user, size").eq("to_device", device.deviceId);
    assertEquals(data, [{ identified: false, sender_user: null, size: 100 }], "sealed: the relay is not recorded as the sender");
    const again = await call("mesh-drop", relay.token, { header, payload });
    assertEquals(again.body, { stored: 0, duplicates: 1 }, "a replay is deduplicated, as `send` does");
    // A second relay carrying the same packet (it travelled two ways): also a duplicate, not a second item.
    const other = await newUser();
    try {
      assertEquals((await call("mesh-drop", other.token, { header, payload })).body, { stored: 0, duplicates: 1 });
    } finally {
      await deleteUser(other);
    }
  });
});

Deno.test("mesh-drop refuses what send would: a swapped payload, a redirected device, a wrong or missing proof, an unopenable header", opts, async () => {
  await withUsers(3, async ([relay, bob, carol]) => {
    const master = await newMasterKey();
    const device = await registerDevice(bob, master);
    const second = await registerDevice(bob, master);
    const { signer } = await setSignedAccess(bob);
    const payload = payloadOf(2);
    const proof = await signer.sign(payload, device.deviceId);
    const drop = (header: Uint8Array, p = payload) => call("mesh-drop", relay.token, { header: toBase64(header), payload: p });

    // A relay swaps the payload for something else: the signature no longer fits.
    assertEquals((await drop(await sealHeader(LOCAL_PUBLIC, 1, device.deviceId, proof), payloadOf(3))).status, 403, "a swapped payload");
    // A relay redirects the header's signature to another device of the same person: it was made for one device.
    assertEquals((await drop(await sealHeader(LOCAL_PUBLIC, 1, second.deviceId, proof))).status, 403, "another device");
    // The proof of another person, a garbled one, none.
    const { signer: stranger } = await setSignedAccess(carol);
    assertEquals((await drop(await sealHeader(LOCAL_PUBLIC, 1, device.deviceId, await stranger.sign(payload, device.deviceId)))).status, 403, "someone else's key");
    assertEquals((await drop(await sealHeader(LOCAL_PUBLIC, 1, device.deviceId, "bm90IGEgc2lnbmF0dXJl"))).status, 403, "garbled");
    // A header for an unknown device, and one that is not a valid routing header at all.
    assertEquals((await drop(await sealHeader(LOCAL_PUBLIC, 1, crypto.randomUUID(), proof))).status, 403, "unknown device");
    assertEquals((await call("mesh-drop", relay.token, { header: toBase64(crypto.getRandomValues(new Uint8Array(80))), payload })).status, 403, "random bytes");
    assertEquals((await drop(await sealHeader(LOCAL_PUBLIC, 9, device.deviceId, proof))).status, 403, "an unknown key id");
    // The old access key is not accepted here (a header can hold only a signature).
    const dave = await newUser();
    try {
      const daveDevice = await registerDevice(dave, await newMasterKey());
      const key = await setAccessKey(dave);
      const sealedKeyHeader = await sealHeader(LOCAL_PUBLIC, 1, daveDevice.deviceId, key);
      assertEquals((await drop(sealedKeyHeader)).status, 403, "an access key is not a signature");
    } finally {
      await deleteUser(dave);
    }
    // And nothing was stored for any of it.
    const { data } = await admin.from("mailbox_items").select("to_device").in("to_device", [device.deviceId, second.deviceId]);
    assertEquals(data, []);
    // Bad requests.
    assertEquals((await call("mesh-drop", relay.token, { header: "", payload })).status, 400);
    assertEquals((await call("mesh-drop", relay.token, { header: "###", payload })).status, 400);
    assertEquals((await call("mesh-drop", relay.token, { payload })).status, 400);
    assert(await sha256(new Uint8Array(1)), "(keep the import used)");
  });
});

Deno.test("mesh-drop: a revoked device and a user with no signing key on file are refused", opts, async () => {
  await withUsers(2, async ([relay, bob]) => {
    const master = await newMasterKey();
    const device = await registerDevice(bob, master);
    const { signer } = await setSignedAccess(bob);
    const payload = payloadOf(4);
    const header = toBase64(await sealHeader(LOCAL_PUBLIC, 1, device.deviceId, await signer.sign(payload, device.deviceId)));
    // A rotation by an older build clears the public key: the old signature proves nothing.
    await setAccessKey(bob);
    assertEquals((await call("mesh-drop", relay.token, { header, payload })).status, 403, "no public key on file");
    // Restore a key, then revoke the device.
    const { signer: again } = await setSignedAccess(bob);
    const header2 = toBase64(await sealHeader(LOCAL_PUBLIC, 1, device.deviceId, await again.sign(payload, device.deviceId)));
    assertEquals((await call("mesh-drop", relay.token, { header: header2, payload })).status, 200);
    await admin.from("devices").update({ revoked_at: new Date().toISOString() }).eq("device_id", device.deviceId);
    const payload2 = payloadOf(5);
    const header3 = toBase64(await sealHeader(LOCAL_PUBLIC, 1, device.deviceId, await again.sign(payload2, device.deviceId)));
    assertEquals((await call("mesh-drop", relay.token, { header: header3, payload: payload2 })).status, 403, "a revoked device");
  });
});
