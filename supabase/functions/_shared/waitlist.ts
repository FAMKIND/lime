// The launch list (LIME-284c2): what the four `waitlist-*` functions share. A browser form posts here, so a request can be a plain HTML form (no JavaScript:
// answered with a redirect to a small page on limemessenger.com) or a script's `fetch` (answered with JSON). Nothing about the visitor is kept: the rate limit counts
// a KEYED HASH of the address and of the caller (never either one), and nothing here logs a body, an address or a token.

import { HttpError } from "./http.ts";
import { toHex } from "./bytes.ts";
import { routingKeysFromEnv } from "./mesh.ts";

export const LISTS = ["launch", "android"] as const;
export type List = typeof LISTS[number];
export const TEACHES = ["k12", "higher_ed", "studio_community", "other"] as const;

/** The public site the visitor goes back to (a redirect target). */
export const siteUrl = (): string => (Deno.env.get("LIME_SITE_URL") ?? "https://limemessenger.com").replace(/\/+$/, "");

/** Where the functions are reached from outside (the links in the confirm email). */
export const functionsUrl = (): string => (Deno.env.get("LIME_WAITLIST_BASE") ?? `${Deno.env.get("SUPABASE_URL") ?? ""}/functions/v1`).replace(/\/+$/, "");

/** Pages that may read the JSON reply (CORS). */
function allowedOrigins(): string[] {
  const extra = (Deno.env.get("LIME_WAITLIST_ORIGINS") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  const site = siteUrl();
  return [site, site.replace("://", "://www."), ...extra];
}

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  return allowedOrigins().includes(origin)
    ? { "access-control-allow-origin": origin, vary: "Origin", "access-control-allow-methods": "POST, GET, OPTIONS", "access-control-allow-headers": "content-type, accept", "access-control-max-age": "600" }
    : { vary: "Origin" };
}

/** The request's fields, from a form post (`application/x-www-form-urlencoded`) or JSON, as strings. At most 4 KB. */
export async function readFields(req: Request): Promise<Record<string, string>> {
  if (req.method === "GET") return Object.fromEntries(new URL(req.url).searchParams);
  if (req.method !== "POST") throw new HttpError(405, "method_not_allowed", "Use POST.");
  const text = await req.text();
  if (text.length > 4096) throw new HttpError(413, "too_large", "The request is too large.");
  const type = (req.headers.get("content-type") ?? "").toLowerCase();
  const out: Record<string, string> = {};
  if (type.includes("application/json")) {
    let value: unknown;
    try { value = JSON.parse(text); } catch { throw new HttpError(400, "bad_request", "The body must be JSON or a form."); }
    if (value === null || typeof value !== "object" || Array.isArray(value)) throw new HttpError(400, "bad_request", "The body must be an object.");
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) if (typeof v === "string") out[k] = v;
    return out;
  }
  for (const [k, v] of new URLSearchParams(text)) out[k] = v;
  return out;
}

/** True when the caller is a script that wants JSON; false for a browser's plain form post or link. */
export const wantsJson = (req: Request): boolean => (req.headers.get("accept") ?? "").includes("application/json");

export function redirect(req: Request, path: string): Response {
  return new Response(null, { status: 303, headers: { location: `${siteUrl()}${path}`, "cache-control": "no-store", "referrer-policy": "no-referrer", ...corsHeaders(req) } });
}

export function reply(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store", ...corsHeaders(req) } });
}

/** A keyed-hash rate-limit bucket for any text (an address or an email), so the table holds neither. The key is the server's mesh secret. */
export async function hashedBucket(label: string, value: string): Promise<string> {
  const secret = [...routingKeysFromEnv().entries()].sort((a, b) => a[0] - b[0]).pop()?.[1] ?? "no-key";
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${label}|${value}`)));
  return `${label}:${toHex(mac.slice(0, 12))}`;
}

/** A random token (192 bits, hex). */
export function newToken(): string {
  return toHex(crypto.getRandomValues(new Uint8Array(24)));
}

export const isToken = (value: unknown): value is string => typeof value === "string" && /^[0-9a-f]{48}$/.test(value);

/** The confirm email: short, and it says how to ignore it. */
export function confirmNotice(confirmUrl: string, list: List): { subject: string; text: string; html: string } {
  const what = list === "android" ? "when lime is on Android" : "when lime is ready";
  const text = `Tap to confirm, and we'll email you once, ${what}.\n\n${confirmUrl}\n\nDidn't ask for this? Ignore it and we'll delete your address in 7 days.`;
  const html = `<p>Tap to confirm, and we'll email you once, ${what}.</p><p><a href="${confirmUrl}" style="display:inline-block;padding:12px 22px;border-radius:999px;background:#a3e18a;color:#131b17;text-decoration:none;font-weight:600">Confirm my email</a></p>` +
    `<p style="color:#555">Didn't ask for this? Ignore it and we'll delete your address in 7 days.</p>`;
  return { subject: "Confirm your email for lime", text, html };
}

/**
 * Wraps a waitlist handler: answers the browser's preflight, adds the CORS headers, and turns any error into JSON for a script or a redirect to the "try again" page for a
 * plain form or link (nothing is echoed back). `fn` gets whether the caller wants JSON.
 */
export function waitlistServe(fn: (req: Request, json: boolean) => Promise<Response>): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(req) });
    const json = wantsJson(req);
    try {
      return await fn(req, json);
    } catch (error) {
      const status = error instanceof HttpError ? error.status : 500;
      const code = error instanceof HttpError ? error.code : "internal";
      if (json) return reply(req, { error: code, message: error instanceof HttpError ? error.message : "Something went wrong." }, status);
      return redirect(req, "/try-again/");
    }
  };
}
