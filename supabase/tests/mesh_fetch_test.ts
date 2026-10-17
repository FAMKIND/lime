// LIME-155: relay download (`mesh-fetch`). The request an offline phone signs, a nearby online phone posts with NO session, and the reply only the
// offline phone can read. Run with ./supabase/test.sh (the local stack, with the local mesh test key).

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { admin, call, deleteUser, newMasterKey, newUser, type TestUser } from "./helpers.ts";
import { fromBase64, fromHex, toBase64, toHex, verifyEd25519 } from "../functions/_shared/bytes.ts";
import { FETCH_SIGN_LABEL, openFetchRequest, parseFetchRequest } from "../functions/_shared/mesh.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };
const LOCAL_PUBLIC = "GyNOPj7N/ovXno/OznB9bEtKB2PTAsuRK1XzXrzX7lY=";
const PKCS8_X25519 = Uint8Array.from([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20]);

type Signer = { deviceId: string; sign: (bytes: Uint8Array) => Promise<Uint8Array> };

/** A device whose Ed25519 key the test holds (the shared helper registers a random, unusable one). */
async function registerSigningDevice(user: TestUser, master?: Awaited<ReturnType<typeof newMasterKey>>): Promise<Signer> {
  master ??= await newMasterKey();
  const pair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const deviceId = crypto.randomUUID();
  const identityKey = toBase64(crypto.getRandomValues(new Uint8Array(32)));
  const signingKey = toBase64(new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)));
  const res = await call("devices-register", user.token, {
    device_id: deviceId, identity_key: identityKey, signing_key: signingKey, master_key: master.publicKey,
    master_signature: await master.sign(`lime-device-v1\n${deviceId}\n${identityKey}\n${signingKey}`),
  });
  if (res.status !== 201) throw new Error(`device registration failed: ${res.status}`);
  return { deviceId, sign: async (bytes) => new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, pair.privateKey, bytes as BufferSource)) };
}

function uuidBytes(uuid: string): Uint8Array {
  const hex = uuid.replaceAll("-", "");
  return Uint8Array.from({ length: 16 }, (_, i) => Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16));
}

type Reply = { secret: CryptoKey; publicKey: Uint8Array };
async function replyKey(): Promise<Reply> {
  const pair = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"]) as CryptoKeyPair;
  return { secret: pair.privateKey, publicKey: new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)) };
}

type Options = { after?: number; ack?: number; limit?: number; expiresIn?: number; nonce?: Uint8Array; signWith?: Signer; reply?: Reply };

/** The sealed request, built as lime_core builds it: 91 canonical bytes, then an Ed25519 signature over "lime-mesh-fetch-v1" || them, sealed. */
async function buildRequest(device: Signer, o: Options = {}): Promise<{ request: string; reply: Reply; nonce: Uint8Array }> {
  const reply = o.reply ?? await replyKey();
  const nonce = o.nonce ?? crypto.getRandomValues(new Uint8Array(16));
  const canonical = new Uint8Array(91);
  const view = new DataView(canonical.buffer);
  canonical[0] = 1;
  canonical.set(uuidBytes(device.deviceId), 1);
  view.setBigInt64(17, BigInt(o.after ?? 0));
  view.setBigInt64(25, BigInt(o.ack ?? -1));
  view.setUint16(33, o.limit ?? 50);
  canonical.set(nonce, 35);
  view.setBigUint64(51, BigInt(Math.floor(Date.now() / 1000) + (o.expiresIn ?? 300)));
  canonical.set(reply.publicKey, 59);
  const label = new TextEncoder().encode("lime-mesh-fetch-v1");
  const toSign = new Uint8Array([...label, ...canonical]);
  const signature = await (o.signWith ?? device).sign(toSign);
  return { request: toBase64(await sealTo(new Uint8Array([...canonical, ...signature]), label)), reply, nonce };
}

async function sealTo(plain: Uint8Array, label: Uint8Array): Promise<Uint8Array> {
  const keyId = 1;
  const pair = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"]) as CryptoKeyPair;
  const ephemeral = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
  const server = await crypto.subtle.importKey("raw", fromBase64(LOCAL_PUBLIC) as BufferSource, { name: "X25519" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "X25519", public: server }, pair.privateKey, 256));
  const hkdf = await crypto.subtle.importKey("raw", shared as BufferSource, "HKDF", false, ["deriveBits"]);
  const info = new Uint8Array([...label, keyId, ...ephemeral]);
  const okm = new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: info as BufferSource }, hkdf, 44 * 8));
  const aes = await crypto.subtle.importKey("raw", okm.slice(0, 32) as BufferSource, "AES-GCM", false, ["encrypt"]);
  const aad = new Uint8Array([keyId, ...ephemeral]);
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: okm.slice(32, 44) as BufferSource, additionalData: aad as BufferSource }, aes, plain as BufferSource));
  return new Uint8Array([...aad, ...sealed]);
}

/** Opens a reply with the request's reply key: ephemeral X25519 || AES-256-GCM(4-byte length || JSON || zeros). */
async function openReply(reply: Reply, sealed: Uint8Array): Promise<{ items: any[]; has_more: boolean; blocked?: boolean }> {
  const ephemeral = sealed.slice(0, 32);
  const peer = await crypto.subtle.importKey("raw", ephemeral as BufferSource, { name: "X25519" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "X25519", public: peer }, reply.secret, 256));
  const hkdf = await crypto.subtle.importKey("raw", shared as BufferSource, "HKDF", false, ["deriveBits"]);
  const info = new Uint8Array([...new TextEncoder().encode("lime-mesh-fetch-reply-v1"), ...ephemeral]);
  const okm = new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: info as BufferSource }, hkdf, 44 * 8));
  const aes = await crypto.subtle.importKey("raw", okm.slice(0, 32) as BufferSource, "AES-GCM", false, ["decrypt"]);
  const plain = new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv: okm.slice(32, 44) as BufferSource, additionalData: ephemeral as BufferSource }, aes, sealed.slice(32) as BufferSource));
  const length = new DataView(plain.buffer).getUint32(0);
  return JSON.parse(new TextDecoder().decode(plain.slice(4, 4 + length)));
}

async function putItems(deviceId: string, sizes: number[]): Promise<number[]> {
  const cursors: number[] = [];
  for (const size of sizes) {
    const bytes = crypto.getRandomValues(new Uint8Array(size));
    const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
    const { data, error } = await admin.from("mailbox_items").insert({
      to_device: deviceId, ciphertext: "\\x" + toHex(bytes), ciphertext_hash: "\\x" + toHex(hash), size, identified: false,
    }).select("cursor").single();
    if (error) throw new Error(error.message);
    cursors.push(data.cursor as number);
  }
  return cursors;
}

const masters = new Map<string, Awaited<ReturnType<typeof newMasterKey>>>();

async function withDevice(run: (user: TestUser, device: Signer, relay: TestUser) => Promise<void>) {
  const user = await newUser();
  const relay = await newUser();
  try {
    const master = await newMasterKey();
    masters.set(user.id, master);
    await run(user, await registerSigningDevice(user, master), relay);
  } finally {
    await deleteUser(user);
    await deleteUser(relay);
  }
}

const post = (request: string, extra: Record<string, string> = {}) => call("mesh-fetch", null, { request }, extra);

Deno.test("mesh-fetch: a signed request with no session returns the device's items, only its owner's reply key can read them", opts, async () => {
  await withDevice(async (_user, device) => {
    const cursors = await putItems(device.deviceId, [100, 200, 300]);
    const { request, reply } = await buildRequest(device);
    const res = await post(request);
    assertEquals(res.status, 200, JSON.stringify(res.body));
    const sealed = fromBase64(res.body.reply);
    assertEquals(sealed.length % 4096, 48, "the reply is padded to 4 KiB steps (plus the 32-byte ephemeral key and the 16-byte tag)");
    const opened = await openReply(reply, sealed);
    assertEquals(opened.items.map((i: any) => i.cursor), cursors);
    assertEquals(opened.has_more, false);
    assertEquals(opened.items[0].size, 100);
    // Nobody else can read it.
    await openReply(await replyKey(), sealed).then(() => assert(false, "opened with a stranger's key"), () => {});
  });
});

Deno.test("mesh-fetch: a session header sent anyway is ignored (the account is not read or needed)", opts, async () => {
  await withDevice(async (_user, device, relay) => {
    await putItems(device.deviceId, [64]);
    const { request, reply } = await buildRequest(device);
    const res = await call("mesh-fetch", relay.token, { request });
    assertEquals(res.status, 200);
    assertEquals((await openReply(reply, fromBase64(res.body.reply))).items.length, 1);
  });
});

Deno.test("mesh-fetch: another device's signature, a changed byte, an expired or too-distant request, a replayed nonce, a revoked or unknown device are all one 403", opts, async () => {
  await withDevice(async (user, device) => {
    const other = await registerSigningDevice(user, masters.get(user.id));
    await putItems(device.deviceId, [50]);
    // Signed by another device's key.
    assertEquals((await post((await buildRequest(device, { signWith: other })).request)).status, 403, "another device's signature");
    // Expired, and further out than 10 minutes.
    assertEquals((await post((await buildRequest(device, { expiresIn: -5 })).request)).status, 403, "expired");
    assertEquals((await post((await buildRequest(device, { expiresIn: 3600 })).request)).status, 403, "too far ahead");
    // Garbage and an unopenable request.
    assertEquals((await post(toBase64(crypto.getRandomValues(new Uint8Array(200))))).status, 403, "random bytes");
    // A request sealed to the routing-header label does not open as a fetch request (separate HKDF labels).
    // A good one works once; the same one again is a replay.
    const good = await buildRequest(device);
    assertEquals((await post(good.request)).status, 200);
    assertEquals((await post(good.request)).status, 403, "the same request twice: the nonce is spent");
    // The same nonce in a freshly signed request is refused too.
    assertEquals((await post((await buildRequest(device, { nonce: good.nonce })).request)).status, 403, "a reused nonce");
    // An unknown device.
    const ghost: Signer = { deviceId: crypto.randomUUID(), sign: device.sign };
    assertEquals((await post((await buildRequest(ghost)).request)).status, 403, "unknown device");
    // Revoked.
    await admin.from("devices").update({ revoked_at: new Date().toISOString() }).eq("device_id", device.deviceId);
    assertEquals((await post((await buildRequest(device)).request)).status, 403, "revoked device");
  });
});

Deno.test("mesh-fetch: ack_through deletes what the phone already kept, and only that", opts, async () => {
  await withDevice(async (_user, device) => {
    const [a, b, c] = await putItems(device.deviceId, [10, 10, 10]);
    const first = await buildRequest(device, { limit: 2 });
    const opened = await openReply(first.reply, fromBase64((await post(first.request)).body.reply));
    assertEquals(opened.items.map((i: any) => i.cursor), [a, b]);
    assertEquals(opened.has_more, true, "one more waits");
    // The next request acknowledges what was kept (through b) and asks for the rest.
    const second = await buildRequest(device, { after: b, ack: b });
    const rest = await openReply(second.reply, fromBase64((await post(second.request)).body.reply));
    assertEquals(rest.items.map((i: any) => i.cursor), [c]);
    const { data } = await admin.from("mailbox_items").select("cursor").eq("to_device", device.deviceId).order("cursor");
    assertEquals((data ?? []).map((r) => r.cursor), [c], "a and b are gone from the server, c is not (it was not acknowledged yet)");
  });
});

Deno.test("mesh-fetch: a reply holds a prefix of the items that fits one Bluetooth frame and says there is more", opts, async () => {
  await withDevice(async (_user, device) => {
    const cursors = await putItems(device.deviceId, [20_000, 20_000, 20_000, 20_000]);
    const req = await buildRequest(device, { limit: 50 });
    const opened = await openReply(req.reply, fromBase64((await post(req.request)).body.reply));
    assert(opened.items.length >= 1 && opened.items.length < 4, `a prefix, not all: ${opened.items.length}`);
    assertEquals(opened.items.map((i: any) => i.cursor), cursors.slice(0, opened.items.length), "never a gap");
    assertEquals(opened.has_more, true);
    // An item too big for the budget on its own: nothing is skipped, the phone is told it is blocked.
    await admin.from("mailbox_items").delete().eq("to_device", device.deviceId);
    await putItems(device.deviceId, [60_000]);
    const big = await buildRequest(device);
    const blocked = await openReply(big.reply, fromBase64((await post(big.request)).body.reply));
    assertEquals(blocked.items.length, 0);
    assertEquals(blocked.blocked, true);
    const { data } = await admin.from("mailbox_items").select("cursor").eq("to_device", device.deviceId);
    assertEquals((data ?? []).length, 1, "nothing was deleted");
  });
});

Deno.test("mesh-fetch: at most 6 requests a minute for one device, and the function logs hold no ids, addresses or tokens", opts, async () => {
  await withDevice(async (user, device, relay) => {
    const since = new Date().toISOString();
    const address = `10.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
    let refused = 0;
    for (let i = 0; i < 8; i++) {
      const res = await call("mesh-fetch", relay.token, { request: (await buildRequest(device)).request }, { "cf-connecting-ip": address });
      if (res.status === 403) refused++;
    }
    assertEquals(refused, 2, "the 7th and 8th request in a minute are refused (one opaque 403)");
    // The logs: grep what the edge runtime wrote for any identifying value.
    try {
      const logs = await new Deno.Command("docker", { args: ["logs", "--since", since, "supabase_edge_runtime_lime"], stdout: "piped", stderr: "piped" }).output();
      const text = new TextDecoder().decode(logs.stdout) + new TextDecoder().decode(logs.stderr);
      for (const secret of [device.deviceId, user.id, address, relay.token, relay.id]) {
        assertEquals(text.includes(secret), false, `the logs must not contain ${secret.slice(0, 6)}…`);
      }
      assertNotEquals(text.length, 0, "the logs were read");
      assert(text.includes("fetch_") || text.includes("rate_limited"), "the refusals logged reason codes");
    } catch (error) {
      if (!(error instanceof Deno.errors.NotFound)) throw error;
      console.warn("docker is not available: the log check was skipped");
    }
  });
});

// What lime_core's test `the_sealed_request_vector_is_pinned` seals (a fixed ephemeral key, a fixed device key, a fixed request).
const RUST_REQUEST_VECTOR = "0113be4feaeaf204c7fd3358fc9c00721881d174278128227ec674f37f7fe97b6d66a8844fbbc8ebf1e812f62be7de27a30795f69bd025d3797a57eba7acf24713ad8e037e1e0e3c033152ce87ee11aacbab90b935ed4db81110e079f4ef1c8dade9f7028d66c2e05a407aa2ced7b1c36dad884a316d506901405abc8462fa5e2ee2ee2158211daa2586ad40053d1a9ee1efe1486005cffb2aeb0f3cb1d6fe3851c727fddef1f36f7fe2f919ae624c2d05c4fcb8ddbdbbeb71601235c9e33dd89b0b037a8667581a42fb2edd";
const RUST_DEVICE_PUBLIC = "/RckOFqgx1tk+3jNYC+h2ZH96/drE8WO1wLqyDXp9hg";
const LOCAL_SECRET = "KILKJyNyeB2broEOGIiyuqZcUVWs9jZM9XtAjY/ZiWA=";

Deno.test("mesh-fetch: the server opens the request lime_core sealed, reads its fields and verifies the device's signature (the cross-language vector)", async () => {
  const opened = await openFetchRequest(new Map([[1, LOCAL_SECRET]]), fromHex(RUST_REQUEST_VECTOR));
  assert(opened, "it opens with the local secret");
  const parsed = parseFetchRequest(opened);
  assert(parsed);
  assertEquals(parsed.deviceId, "0a0b0c0d-0e0f-4a1b-8c2d-3e4f5a6b7c8d");
  assertEquals([parsed.after, parsed.ackThrough, parsed.limit, parsed.expiresAt], [7, 5, 50, 1_900_000_300]);
  assertEquals(toHex(parsed.nonce), "11".repeat(16));
  assertEquals(toHex(parsed.replyKey), "22".repeat(32));
  const signed = new Uint8Array([...FETCH_SIGN_LABEL, ...parsed.canonical]);
  assert(await verifyEd25519(fromBase64(RUST_DEVICE_PUBLIC), parsed.signature, signed), "the device's signature verifies");
  // A routing-header-labelled opener does not open it.
  const { openRoutingHeader } = await import("../functions/_shared/mesh.ts");
  assertEquals(await openRoutingHeader(new Map([[1, LOCAL_SECRET]]), fromHex(RUST_REQUEST_VECTOR)), null);
});
