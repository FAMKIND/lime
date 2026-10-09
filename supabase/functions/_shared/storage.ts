// Storage helpers for the blob store (LIME-98b). The buckets are private: every read and write goes
// through an Edge Function that checks who is asking and hands out a short-lived signed URL.

import { admin } from "./db.ts";
import { HttpError } from "./http.ts";

export const AVATAR_BUCKET = "public-avatars";
export const BLOB_BUCKET = "blobs";
export const MAX_AVATAR_BYTES = 1024 * 1024;
export const SIGNED_URL_SECONDS = 300;

function intFromEnv(name: string, fallback: number): number {
  const value = Number.parseInt(Deno.env.get(name) ?? "", 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

export const blobConfig = {
  /** Largest single blob, in bytes (the bucket enforces it too). */
  maxBlobBytes: () => intFromEnv("LIME_MAX_BLOB_BYTES", 25 * 1024 * 1024),
  /** Total bytes one user may keep, and how many blobs. */
  quotaBytes: () => intFromEnv("LIME_BLOB_QUOTA_BYTES", 200 * 1024 * 1024),
  quotaCount: () => intFromEnv("LIME_BLOB_QUOTA_COUNT", 500),
  /** Avatar and blob calls per minute per user. */
  perMinute: () => intFromEnv("LIME_RATE_BLOB_PER_MIN", 60),
};

/** A signed URL as the path and query the client's transport adds its own base URL to. */
export function relative(signedUrl: string): string {
  const url = new URL(signedUrl);
  return url.pathname + url.search;
}

export async function signedUpload(bucket: string, path: string): Promise<{ url: string; token: string }> {
  const { data, error } = await admin().storage.from(bucket).createSignedUploadUrl(path, { upsert: true });
  if (error || !data) throw new HttpError(500, "internal");
  return { url: relative(data.signedUrl), token: data.token };
}

export async function signedDownload(bucket: string, path: string): Promise<string> {
  const { data, error } = await admin().storage.from(bucket).createSignedUrl(path, SIGNED_URL_SECONDS);
  if (error || !data) throw new HttpError(404, "not_found", "No such file.");
  return relative(data.signedUrl);
}

/** The size of a stored object, or null when it is not there. */
export async function objectSize(bucket: string, path: string): Promise<number | null> {
  const slash = path.lastIndexOf("/");
  const folder = slash < 0 ? "" : path.slice(0, slash);
  const name = slash < 0 ? path : path.slice(slash + 1);
  const { data, error } = await admin().storage.from(bucket).list(folder, { search: name, limit: 5 });
  if (error) throw new HttpError(500, "internal");
  const found = (data ?? []).find((o) => o.name === name);
  const size = (found?.metadata as { size?: number } | null)?.size;
  return typeof size === "number" ? size : found ? 0 : null;
}

export async function removeObject(bucket: string, path: string): Promise<void> {
  const { error } = await admin().storage.from(bucket).remove([path]);
  if (error) throw new HttpError(500, "internal");
}
