// The sealed routing header of a mesh packet (LIME-140). A phone that carries mail over the mesh cannot read where it goes: the header
// (the recipient device and the signed proof, as JSON) is sealed to the SERVER's mesh public key, so only `mesh-drop` can open it.
//
//   header = key_id (1 byte) || ephemeral X25519 public key (32 bytes) || AES-256-GCM ciphertext and tag
//   shared = X25519(server secret, ephemeral public)
//   key (32) || nonce (12) = HKDF-SHA256(salt = none, ikm = shared, info = "lime-mesh-header-v1" || key_id || ephemeral public), 44 bytes
//   AES-256-GCM, aad = key_id || ephemeral public
//
// The ephemeral key is new for every packet, so the derived nonce is never reused with a key. `lime_core` seals; this opens.

const INFO = new TextEncoder().encode("lime-mesh-header-v1");
const PKCS8_X25519_PREFIX = Uint8Array.from([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x04, 0x22, 0x04, 0x20]);

/** The server's mesh secret keys by key id (today one: id 1, from `MESH_ROUTING_SECRET_KEY`, base64 of the 32-byte X25519 secret). */
export function routingKeysFromEnv(): Map<number, string> {
  const keys = new Map<number, string>();
  const first = Deno.env.get("MESH_ROUTING_SECRET_KEY");
  if (first) keys.set(1, first);
  return keys;
}

function fromB64(text: string): Uint8Array {
  const binary = atob(text.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (text.length % 4)) % 4));
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

/** The plaintext of a header, or null when it is not a valid header for one of our keys (a wrong key id, a changed byte, anything). */
export async function openRoutingHeader(keys: Map<number, string>, header: Uint8Array): Promise<Uint8Array | null> {
  return await openSealed(keys, header, INFO);
}

/**
 * Opens something sealed to the server's mesh key (`key_id || ephemeral X25519 public || AES-256-GCM`) with its own HKDF label: the routing header
 * ("lime-mesh-header-v1") and the relay-fetch request ("lime-mesh-fetch-v1") use the same construction and never open each other's.
 */
export async function openSealed(keys: Map<number, string>, header: Uint8Array, label: Uint8Array): Promise<Uint8Array | null> {
  try {
    if (header.length < 1 + 32 + 16) return null;
    const keyId = header[0];
    const secret = keys.get(keyId);
    if (!secret) return null;
    const raw = fromB64(secret);
    if (raw.length !== 32) return null;
    const ephemeral = header.slice(1, 33);
    const privateKey = await crypto.subtle.importKey("pkcs8", new Uint8Array([...PKCS8_X25519_PREFIX, ...raw]), { name: "X25519" }, false, ["deriveBits"]);
    const publicKey = await crypto.subtle.importKey("raw", ephemeral, { name: "X25519" }, false, []);
    const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "X25519", public: publicKey }, privateKey, 256));
    const hkdfKey = await crypto.subtle.importKey("raw", shared, "HKDF", false, ["deriveBits"]);
    const info = new Uint8Array([...label, keyId, ...ephemeral]);
    const okm = new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info }, hkdfKey, 44 * 8));
    const aesKey = await crypto.subtle.importKey("raw", okm.slice(0, 32), "AES-GCM", false, ["decrypt"]);
    const aad = new Uint8Array([keyId, ...ephemeral]);
    return new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv: okm.slice(32, 44), additionalData: aad }, aesKey, header.slice(33)));
  } catch {
    return null;
  }
}

const FETCH_LABEL = new TextEncoder().encode("lime-mesh-fetch-v1");
const REPLY_LABEL = new TextEncoder().encode("lime-mesh-fetch-reply-v1");
export const FETCH_SIGN_LABEL = FETCH_LABEL;

/** The relay-fetch request, opened. Null when it does not open (the same one opaque refusal as a bad routing header). */
export async function openFetchRequest(keys: Map<number, string>, sealed: Uint8Array): Promise<Uint8Array | null> {
  return await openSealed(keys, sealed, FETCH_LABEL);
}

/** A parsed fetch request: 91 canonical bytes then a 64-byte device signature over "lime-mesh-fetch-v1" || the 91 bytes. */
export type FetchRequest = {
  canonical: Uint8Array; signature: Uint8Array; deviceId: string; after: number; ackThrough: number; limit: number;
  nonce: Uint8Array; expiresAt: number; replyKey: Uint8Array;
};

export const FETCH_CANONICAL_BYTES = 91;

export function parseFetchRequest(plain: Uint8Array): FetchRequest | null {
  if (plain.length !== FETCH_CANONICAL_BYTES + 64 || plain[0] !== 1) return null;
  const view = new DataView(plain.buffer, plain.byteOffset, plain.byteLength);
  const hex = Array.from(plain.slice(1, 17), (b) => b.toString(16).padStart(2, "0")).join("");
  const deviceId = `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  const after = Number(view.getBigInt64(17));
  const ackThrough = Number(view.getBigInt64(25));
  const limit = view.getUint16(33);
  return {
    canonical: plain.slice(0, FETCH_CANONICAL_BYTES), signature: plain.slice(FETCH_CANONICAL_BYTES), deviceId, after, ackThrough, limit,
    nonce: plain.slice(35, 51), expiresAt: Number(view.getBigUint64(51)), replyKey: plain.slice(59, 91),
  };
}

/** Pads to 4 KiB steps: a 4-byte length, the bytes, zeros. A relay sees only the bucket, not how many items there were. */
export function padReply(plain: Uint8Array): Uint8Array {
  const total = Math.ceil((4 + plain.length) / 4096) * 4096;
  const out = new Uint8Array(total);
  new DataView(out.buffer).setUint32(0, plain.length);
  out.set(plain, 4);
  return out;
}

/** Encrypts the reply so only the holder of `replyKey`'s secret can read it: ephemeral X25519 || AES-256-GCM, padded to 4 KiB steps. */
export async function sealFetchReply(replyKey: Uint8Array, plain: Uint8Array): Promise<Uint8Array> {
  const pair = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"]) as CryptoKeyPair;
  const ephemeral = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
  const peer = await crypto.subtle.importKey("raw", replyKey as BufferSource, { name: "X25519" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "X25519", public: peer }, pair.privateKey, 256));
  const hkdf = await crypto.subtle.importKey("raw", shared as BufferSource, "HKDF", false, ["deriveBits"]);
  const info = new Uint8Array([...REPLY_LABEL, ...ephemeral]);
  const okm = new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: info as BufferSource }, hkdf, 44 * 8));
  const aes = await crypto.subtle.importKey("raw", okm.slice(0, 32) as BufferSource, "AES-GCM", false, ["encrypt"]);
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: okm.slice(32, 44) as BufferSource, additionalData: ephemeral as BufferSource }, aes, padReply(plain) as BufferSource));
  return new Uint8Array([...ephemeral, ...sealed]);
}

/** The fingerprint of a mesh key's PUBLIC half: the first 16 hex characters of SHA-256(public key). The phone computes the same from the key it pins. */
export async function meshKeyFingerprint(secretB64: string): Promise<string | null> {
  try {
    const raw = fromB64(secretB64);
    if (raw.length !== 32) return null;
    // The public key is the secret times the curve's base point (u = 9): derive it with the base point as the "peer".
    const privateKey = await crypto.subtle.importKey("pkcs8", new Uint8Array([...PKCS8_X25519_PREFIX, ...raw]), { name: "X25519" }, false, ["deriveBits"]);
    const basePoint = await crypto.subtle.importKey("raw", Uint8Array.from([9, ...new Array(31).fill(0)]), { name: "X25519" }, false, []);
    const publicKey = new Uint8Array(await crypto.subtle.deriveBits({ name: "X25519", public: basePoint }, privateKey, 256));
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", publicKey as BufferSource));
    return [...digest.slice(0, 8)].map((b) => b.toString(16).padStart(2, "0")).join("");
  } catch {
    return null;
  }
}
