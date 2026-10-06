import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { HttpError } from "./http.ts";
import { config } from "./config.ts";

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

/** The signed-in user for the request's bearer token. Throws 401 if there is none. */
export async function requireUser(req: Request): Promise<string> {
  const header = req.headers.get("authorization") ?? "";
  const match = /^Bearer (.+)$/i.exec(header);
  if (!match) throw new HttpError(401, "unauthorized", "A user token is required.");
  const { data, error } = await admin().auth.getUser(match[1]);
  if (error || !data.user) throw new HttpError(401, "unauthorized", "A user token is required.");
  return data.user.id;
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

export { config };
