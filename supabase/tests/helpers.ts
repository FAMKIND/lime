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

export function sessionIdOf(token: string): string {
  const part = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(part + "=".repeat((4 - (part.length % 4)) % 4))).session_id;
}

/**
 * A throwaway user with a session that has already passed BOTH sign-in steps (the proof record is
 * written directly, as the account functions would). Use `newUnverifiedUser` for a session that
 * has not.
 */
export async function newUser(): Promise<TestUser> {
  const user = await newUnverifiedUser();
  const { error } = await admin.from("auth_proofs").upsert({
    session_id: sessionIdOf(user.token), user_id: user.id, password_ok: true, code_ok: true, verified_at: new Date().toISOString(),
  });
  if (error) throw new Error(`could not mark the session verified: ${error.message}`);
  return user;
}

export async function newUnverifiedUser(): Promise<TestUser> {
  const email = `t-${crypto.randomUUID()}@example.invalid`;
  const password = crypto.randomUUID();
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (error || !data.user) throw new Error(`could not create a throwaway user: ${error?.message}`);
  const anon = createClient(API_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const signedIn = await anon.auth.signInWithPassword({ email, password });
  if (signedIn.error || !signedIn.data.session) throw new Error("could not sign in the throwaway user");
  return { id: data.user.id, token: signedIn.data.session.access_token, email };
}

export const MAIL_URL = Deno.env.get("LIME_MAIL_URL") ?? "http://127.0.0.1:54324";

/** The newest emailed 6-digit code for an address, read from the local mail catcher (Mailpit). */
export async function emailedCode(email: string, notBefore = 0): Promise<string> {
  const query = encodeURIComponent(`to:${email}`);
  for (let attempt = 0; attempt < 40; attempt++) {
    const found = await (await fetch(`${MAIL_URL}/api/v1/search?query=${query}`)).json() as {
      messages?: { ID: string; Created: string }[];
    };
    const fresh = (found.messages ?? []).filter((m) => new Date(m.Created).getTime() >= notBefore)
      .sort((a, b) => (a.Created < b.Created ? 1 : -1));
    if (fresh.length > 0) {
      const message = await (await fetch(`${MAIL_URL}/api/v1/message/${fresh[0].ID}`)).json() as { Text?: string; HTML?: string };
      const match = /\b(\d{6,8})\b/.exec((message.Text ?? "") + " " + (message.HTML ?? ""));
      if (match) return match[1];
    }
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error("no code arrived in the local mail catcher");
}

export async function clearMailbox(email: string) {
  await fetch(`${MAIL_URL}/api/v1/search?query=${encodeURIComponent(`to:${email}`)}`, { method: "DELETE" });
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
export async function call(fn: string, token: string | null, body: unknown, extraHeaders: Record<string, string> = {}): Promise<{ status: number; body: any }> {
  // Each call comes from its own made-up address unless a test says otherwise, so the per-address
  // limits only trip in the tests that mean them to.
  const headers: Record<string, string> = { "content-type": "application/json" };
  // Only the local stack takes a made-up address: a real project sits behind Cloudflare, which refuses
  // a forged one (error 1000).
  if (API_URL.startsWith("http://127.0.0.1") || API_URL.startsWith("http://localhost")) {
    headers["cf-connecting-ip"] = extraHeaders["cf-connecting-ip"] ??
      `10.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
  }
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

/** Supabase Auth allows one email to an address per second (config max_frequency): wait it out. */
export const pause = (ms = 1100) => new Promise((r) => setTimeout(r, ms));

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
