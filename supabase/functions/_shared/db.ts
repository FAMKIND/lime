import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { HttpError } from "./http.ts";
import { accountConfig, config } from "./config.ts";

let cached: SupabaseClient | undefined;

/** The service-role client. Server-side only; the key never leaves the function runtime. */
export function admin(): SupabaseClient {
  if (!cached) {
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) throw new HttpError(500, "misconfigured");
    cached = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  }
  return cached;
}

/** A signed-in Auth session: who it is and which session (the JWT's `session_id` claim). */
export type Session = { userId: string; sessionId: string; email: string | null; token: string };

export function sessionIdOf(token: string): string | null {
  try {
    const part = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(part + "=".repeat((4 - (part.length % 4)) % 4)));
    return typeof claims.session_id === "string" ? claims.session_id : null;
  } catch {
    return null;
  }
}

/** The session for the request's bearer token, verified or not. Throws 401 if there is none. */
export async function requireSession(req: Request): Promise<Session> {
  const header = req.headers.get("authorization") ?? "";
  const match = /^Bearer (.+)$/i.exec(header);
  const unauthorized = new HttpError(401, "unauthorized", "A user token is required.");
  if (!match) throw unauthorized;
  const { data, error } = await admin().auth.getUser(match[1]);
  const sessionId = sessionIdOf(match[1]);
  if (error || !data.user || !sessionId) throw unauthorized;
  return { userId: data.user.id, sessionId, email: data.user.email ?? null, token: match[1] };
}

/** True when this session passed BOTH the password and the emailed code. */
export async function isVerified(sessionId: string): Promise<boolean> {
  const { data, error } = await admin()
    .from("auth_proofs").select("password_ok, code_ok").eq("session_id", sessionId).maybeSingle();
  if (error) throw new HttpError(500, "internal");
  return !!data && data.password_ok === true && data.code_ok === true;
}

/**
 * The signed-in user, from a **verified** session only (a password and an emailed code). A session
 * that passed only one of them can do nothing: this is how the server enforces the two steps.
 */
export async function requireUser(req: Request): Promise<string> {
  const session = await requireSession(req);
  if (!(await isVerified(session.sessionId))) {
    throw new HttpError(403, "not_verified", "Finish signing in: this session has not passed both steps.");
  }
  return session.userId;
}

/** The caller's own, non-revoked device. */
export async function requireDevice(userId: string, deviceId: unknown) {
  if (typeof deviceId !== "string") throw new HttpError(400, "bad_request", "device_id is required.");
  const { data, error } = await admin()
    .from("devices")
    .select("device_id, user_id, revoked_at")
    .eq("device_id", deviceId)
    .maybeSingle();
  if (error) throw new HttpError(500, "internal");
  if (!data || data.user_id !== userId || data.revoked_at !== null) {
    throw new HttpError(403, "forbidden", "That device is not yours, or it was revoked.");
  }
  return data;
}

/** Counts `cost` against a bucket; throws 429 when the limit is passed. */
export async function rateLimit(bucket: string, cost: number, limit: number, windowSeconds: number) {
  const { data, error } = await admin().rpc("take_rate_limit", {
    p_bucket: bucket,
    p_cost: cost,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });
  if (error) {
    console.error("rate limit call failed", error.code);
    throw new HttpError(500, "internal");
  }
  if (data !== true) throw new HttpError(429, "rate_limited", "Too many requests. Try again shortly.");
}

export { accountConfig, config };
