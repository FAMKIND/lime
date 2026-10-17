// The sealed-access check and the mailbox store, shared by `send` and `mesh-drop` (LIME-140): the same proof, the same rules, one copy.
//
// A sealed proof is `{ signed }` (LIME-139: an Ed25519 signature over "lime-access-v2" || SHA-256(ciphertext) || the device's 16 UUID bytes,
// checked against the recipient's public key) or, during the overlap, `{ sealed }` (the access key; `mesh-drop` does not take it).

import { constantTimeEqual, fromBase64, fromPgBytea, sha256, toPgBytea, uuidBytes, verifyEd25519 } from "./bytes.ts";
import { HttpError } from "./http.ts";

export type Access = { hash: Uint8Array | null; publicKey: Uint8Array | null };

/** What a signed send signs: a label, SHA-256 of the ciphertext and the recipient device's 16 raw UUID bytes (one message to one device only). */
export const SIGNED_LABEL = new TextEncoder().encode("lime-access-v2");

/** Why an access was refused, for the function logs only (LIME-142-fix2): a short code, never an id, key or token. The phone still sees the one 403. */
export type DenyReason =
  | "no_public_key" | "bad_signature" | "bad_access_key" | "no_proof" | "header_unopenable" | "header_fields" | "unknown_device" | "revoked_device"
  // mesh-fetch (LIME-155)
  | "fetch_unopenable" | "fetch_fields" | "fetch_expired" | "fetch_device" | "fetch_signature" | "nonce_used" | "rate_limited";

export const accessDenied = (reason?: DenyReason) => {
  console.warn(JSON.stringify({ event: "access_denied", reason: reason ?? "unspecified" }));
  return new HttpError(403, "access_denied", "The access key was not accepted.");
};

// deno-lint-ignore no-explicit-any
type Db = any;

/** The recipient user's stored proofs (cached per call). */
export async function loadAccess(db: Db, userId: string, cache: Map<string, Access>): Promise<Access> {
  if (!cache.has(userId)) {
    const { data } = await db.from("delivery_access").select("access_key_hash, access_public_key").eq("user_id", userId).maybeSingle();
    cache.set(userId, {
      hash: data?.access_key_hash ? fromPgBytea(data.access_key_hash as string) : null,
      publicKey: data?.access_public_key ? fromPgBytea(data.access_public_key as string) : null,
    });
  }
  return cache.get(userId)!;
}

/**
 * Checks one recipient's sealed proof. Returns the key the rate limit is counted against (per recipient, never per sender). Anything wrong
 * (no proof, a wrong or short signature, no key on file, a wrong access key) throws the same 403, so nothing leaks about which part failed.
 * `allowAccessKey` is false for `mesh-drop`, which takes only signatures.
 */
export async function verifySealed(
  stored: Access, access: { signed?: unknown; sealed?: unknown }, toDevice: string, ciphertextHash: Uint8Array, allowAccessKey = true,
): Promise<Uint8Array> {
  if (typeof access.signed === "string") {
    let signature: Uint8Array;
    try {
      signature = fromBase64(access.signed);
    } catch {
      throw accessDenied("bad_signature");
    }
    if (!stored.publicKey) throw accessDenied("no_public_key");
    if (signature.length !== 64) throw accessDenied("bad_signature");
    const message = new Uint8Array(SIGNED_LABEL.length + 32 + 16);
    message.set(SIGNED_LABEL, 0);
    message.set(ciphertextHash, SIGNED_LABEL.length);
    message.set(uuidBytes(toDevice), SIGNED_LABEL.length + 32);
    if (!(await verifyEd25519(stored.publicKey, signature, message))) throw accessDenied("bad_signature");
    return await sha256(stored.publicKey);
  }
  if (!allowAccessKey || typeof access.sealed !== "string") throw accessDenied("no_proof");
  let presented: Uint8Array;
  try {
    presented = fromBase64(access.sealed);
  } catch {
    throw accessDenied("bad_access_key");
  }
  if (presented.length !== 16) throw accessDenied("bad_access_key");
  const presentedHash = await sha256(presented);
  if (!stored.hash || !constantTimeEqual(stored.hash, presentedHash)) throw accessDenied("bad_access_key");
  return presentedHash;
}

/** Wakes the devices' Realtime channels (a private channel only its owner may join) with { type: "new" } and no content. */
export async function nudge(deviceIds: string[]): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key || deviceIds.length === 0) return;
  try {
    await fetch(`${url}/realtime/v1/api/broadcast`, {
      method: "POST",
      headers: { "content-type": "application/json", apikey: key, authorization: `Bearer ${key}` },
      body: JSON.stringify({
        messages: deviceIds.map((id) => ({ topic: `device:${id}`, event: "new", payload: { type: "new" }, private: true })),
      }),
    });
  } catch {
    // A missed nudge is harmless: the device also fetches when it opens.
  }
}

export type MailboxRow = {
  to_device: string; ciphertext: string; ciphertext_hash: string; size: number; identified: boolean; sender_user: string | null;
};

/** One sealed row for a device (no sender recorded). */
export function sealedRow(toDevice: string, ciphertext: Uint8Array, ciphertextHash: Uint8Array, identified = false, senderUser: string | null = null): MailboxRow {
  return {
    to_device: toDevice,
    ciphertext: toPgBytea(ciphertext),
    ciphertext_hash: toPgBytea(ciphertextHash),
    size: ciphertext.length,
    identified,
    sender_user: identified ? senderUser : null,
  };
}

/** Stores the rows, de-duplicated by SHA-256(ciphertext) per recipient device (a repeat is ignored), and nudges the devices that got one. */
export async function storeRows(db: Db, rows: MailboxRow[]): Promise<string[]> {
  const { data: stored, error } = await db
    .from("mailbox_items")
    .upsert(rows, { onConflict: "to_device,ciphertext_hash", ignoreDuplicates: true })
    .select("to_device");
  if (error) throw new HttpError(500, "internal");
  const storedDevices = (stored ?? []).map((s: { to_device: string }) => s.to_device);
  await nudge(storedDevices);
  return storedDevices;
}
