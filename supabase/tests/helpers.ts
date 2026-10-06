// Test helpers: throwaway users through the local admin API, device keys, and function calls.
// These run against the LOCAL stack only (see supabase/test.sh).

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { sha256, toBase64 } from "../functions/_shared/bytes.ts";

export const API_URL = must("LIME_API_URL");
export const ANON_KEY = must("LIME_ANON_KEY");
export const SERVICE_ROLE_KEY = must("LIME_SERVICE_ROLE_KEY");
export const DB_URL = Deno.env.get("LIME_DB_URL") ?? "";

function must(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not set (run ./supabase/test.sh)`);
  return value;
}

export const admin: SupabaseClient = createClient(API_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

export type TestUser = { id: string; token: string; email: string };

export async function newUser(): Promise<TestUser> {
  const email = `t-${crypto.randomUUID()}@example.invalid`;
  const password = crypto.randomUUID();
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (error || !data.user) throw new Error(`could not create a throwaway user: ${error?.message}`);
  const anon = createClient(API_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const signedIn = await anon.auth.signInWithPassword({ email, password });
  if (signedIn.error || !signedIn.data.session) throw new Error("could not sign in the throwaway user");
  return { id: data.user.id, token: signedIn.data.session.access_token, email };
}

export async function deleteUser(user: TestUser) {
  await admin.auth.admin.deleteUser(user.id);
}

export function randomBytes(n: number): Uint8Array {
  const out = new Uint8Array(n);
  for (let i = 0; i < n; i += 65536) crypto.getRandomValues(out.subarray(i, Math.min(n, i + 65536)));
  return out;
}

export type MasterKey = { publicKey: string; sign: (message: string) => Promise<string> };

export async function newMasterKey(): Promise<MasterKey> {
  const pair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const publicKey = toBase64(new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)));
  return {
    publicKey,
    sign: async (message) =>
      toBase64(new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, pair.privateKey, new TextEncoder().encode(message)))),
  };
}

export type TestDevice = { deviceId: string; identityKey: string; signingKey: string };

/** Registers a new device for `user`, cross-signed by `master`. */
export async function registerDevice(user: TestUser, master: MasterKey): Promise<TestDevice> {
  const device = { deviceId: crypto.randomUUID(), identityKey: toBase64(randomBytes(32)), signingKey: toBase64(randomBytes(32)) };
  const signature = await master.sign(`lime-device-v1\n${device.deviceId}\n${device.identityKey}\n${device.signingKey}`);
  const res = await call("devices-register", user.token, {
    device_id: device.deviceId,
    identity_key: device.identityKey,
    signing_key: device.signingKey,
    master_key: master.publicKey,
    master_signature: signature,
  });
  if (res.status !== 201) throw new Error(`device registration failed: ${res.status} ${JSON.stringify(res.body)}`);
  return device;
}

/** An Edge Function call. `token` null sends no Authorization header at all. */
export async function call(fn: string, token: string | null, body: unknown): Promise<{ status: number; body: any }> {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (token) {
    headers.authorization = `Bearer ${token}`;
    headers.apikey = ANON_KEY;
  }
  const res = await fetch(`${API_URL}/functions/v1/${fn}`, { method: "POST", headers, body: JSON.stringify(body) });
  const text = await res.text();
  let parsed: unknown = text;
  try {
    parsed = JSON.parse(text);
  } catch { /* leave as text */ }
  return { status: res.status, body: parsed };
}

export function otk(count: number, prefix = "k"): { key_id: string; key: string }[] {
  return Array.from({ length: count }, (_, i) => ({ key_id: `${prefix}${i}`, key: toBase64(randomBytes(32)) }));
}

export const sha256Bytes = sha256;

/** Gives `user` an access key (returns the key as base64); the server only ever gets its hash. */
export async function setAccessKey(user: TestUser): Promise<string> {
  const accessKey = randomBytes(16);
  const res = await call("delivery-access-set", user.token, { access_key_hash: toBase64(await sha256Bytes(accessKey)) });
  if (res.status !== 200) throw new Error(`delivery-access-set failed: ${res.status}`);
  return toBase64(accessKey);
}

export function ciphertext(size = 64): string {
  return toBase64(randomBytes(size));
}
