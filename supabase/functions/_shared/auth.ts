// Helpers for the account functions: calls to Supabase Auth, masking, client address.

import { admin, sessionIdOf } from "./db.ts";
import { HttpError } from "./http.ts";

/** A call to Supabase Auth with the project's public key (the same call a client could make). */
export async function authCall(path: string, body: unknown, opts: { query?: string } = {}): Promise<{ status: number; body: any }> {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !key) throw new HttpError(500, "misconfigured");
  const res = await fetch(`${url}/auth/v1${path}${opts.query ?? ""}`, {
    method: "POST",
    headers: { "content-type": "application/json", apikey: key },
    body: JSON.stringify(body),
  });
  let parsed: unknown = null;
  try {
    parsed = await res.json();
  } catch { /* an empty body */ }
  return { status: res.status, body: parsed };
}

/** "s•••@famkind.com": enough to recognise your own address, not to learn someone else's. */
export function maskEmail(email: string): string {
  const [local, domain] = email.split("@");
  if (!domain) return "•••";
  return `${local.slice(0, 1)}•••@${domain}`;
}

/**
 * The caller's address for rate limiting: Cloudflare's header on the platform, else the LAST entry of
 * `x-forwarded-for` (the one the platform's own proxy appended; earlier entries can be forged).
 */
export function clientIp(req: Request): string {
  const cloudflare = req.headers.get("cf-connecting-ip");
  if (cloudflare) return cloudflare.trim();
  const forwarded = (req.headers.get("x-forwarded-for") ?? "").split(",").map((p) => p.trim()).filter(Boolean);
  return forwarded[forwarded.length - 1] ?? "unknown";
}

export function normaliseEmail(value: unknown): string {
  const email = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (email.length < 3 || email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw new HttpError(400, "bad_request", "That does not look like an email address.");
  }
  return email;
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

// The username rules are the web app's (public/js/store.js, server/lib/util.mjs).
const RESERVED = new Set([
  "admin", "administrator", "lime", "support", "help", "root", "system", "moderator", "mod", "staff", "team",
  "official", "security", "abuse", "postmaster", "webmaster", "null", "undefined", "api", "www", "mail", "info",
  "contact", "billing", "settings", "account", "me", "you", "everyone", "all", "here", "famkind",
]);

export function usernameError(value: string): string | null {
  if (value.length < 3 || value.length > 20) return "Use 3 to 20 characters.";
  if (!/^[A-Za-z0-9._]+$/.test(value)) return "Use only letters, numbers, dots and underscores.";
  if (value.startsWith(".") || value.endsWith(".")) return "A username can’t start or end with a dot.";
  if (RESERVED.has(value.toLowerCase())) return "That username is reserved. Try another.";
  return null;
}

export const MIN_PASSWORD_LENGTH = 10;
export const MAX_CODE_ATTEMPTS = 5;
export const RESEND_AFTER_SECONDS = 30;

/**
 * Changing a password ends the account's existing sessions, so after the code and the new password
 * have both been proven, sign in with that password to get a fresh session and mark it verified.
 */
export async function verifiedSessionFor(email: string, password: string, userId: string) {
  const signedIn = await authCall("/token", { email, password }, { query: "?grant_type=password" });
  const session = signedIn.body;
  if (signedIn.status !== 200 || !session?.access_token) throw new HttpError(500, "internal");
  const sessionId = sessionIdOf(session.access_token);
  if (!sessionId) throw new HttpError(500, "internal");
  const { error } = await admin().from("auth_proofs").upsert({
    session_id: sessionId, user_id: userId, password_ok: true, code_ok: true, verified_at: new Date().toISOString(),
  });
  if (error) throw new HttpError(500, "internal");
  return {
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_in: session.expires_in,
    expires_at: session.expires_at,
    user_id: userId,
  };
}

/**
 * An email address or a username to the account's email, on the server (so the phone never needs
 * the full email of a username). Returns null when there is no such account.
 */
export async function resolveEmail(identifier: string): Promise<string | null> {
  const raw = identifier.trim();
  if (raw.includes("@") && !raw.startsWith("@")) {
    try {
      return normaliseEmail(raw);
    } catch {
      return null;
    }
  }
  const username = raw.replace(/^@/, "");
  if (usernameError(username)) return null;
  const { data } = await admin().rpc("resolve_username", { p_username: username });
  const row = Array.isArray(data) ? data[0] : null;
  return row?.email ?? null;
}

/** The emailed code is 6 digits as configured here, but the hosted project's own setting can differ
 *  (it once sent 8): accept 6 to 8 digits so a settings drift cannot lock people out. */
export const CODE_PATTERN = /^\d{6,8}$/;

/**
 * Asks Supabase Auth to email a code. A rate-limited send (Auth allows one email per address per
 * interval, and a project-wide hourly cap) becomes a clear "wait N seconds" error; any other
 * failure becomes "could not send". Never reports success for a send that did not happen.
 */
export async function sendCode(email: string, createUser: boolean): Promise<void> {
  const sent = await authCall("/otp", { email, create_user: createUser });
  if (sent.status === 200) return;
  const text = String(sent.body?.msg ?? sent.body?.message ?? "");
  if (sent.status === 429 || sent.body?.error_code === "over_email_send_rate_limit" || /only request this after/i.test(text)) {
    const seconds = /after (\d+) second/i.exec(text)?.[1];
    throw new HttpError(
      429,
      "too_soon",
      seconds ? `Please wait ${seconds} seconds before asking for another code.` : "Please wait a little before asking for another code.",
    );
  }
  throw new HttpError(502, "email_failed", "We could not send the code. Try again in a moment.");
}
