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
    const info = new Uint8Array([...INFO, keyId, ...ephemeral]);
    const okm = new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info }, hkdfKey, 44 * 8));
    const aesKey = await crypto.subtle.importKey("raw", okm.slice(0, 32), "AES-GCM", false, ["decrypt"]);
    const aad = new Uint8Array([keyId, ...ephemeral]);
    return new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv: okm.slice(32, 44), additionalData: aad }, aesKey, header.slice(33)));
  } catch {
    return null;
  }
}
