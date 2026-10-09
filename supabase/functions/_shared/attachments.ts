// Helpers for chunked attachments (LIME-98c).

import { admin } from "./db.ts";
import { BLOB_BUCKET } from "./storage.ts";

function intFromEnv(name: string, fallback: number): number {
  const value = Number.parseInt(Deno.env.get(name) ?? "", 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

export const attachmentConfig = {
  /** Largest file, in ciphertext bytes (50 MB of content plus the per-chunk tags). */
  maxBytes: () => intFromEnv("LIME_MAX_ATTACHMENT_BYTES", 51 * 1024 * 1024),
  /** Total bytes and count one user may keep on the server at a time. */
  quotaBytes: () => intFromEnv("LIME_ATTACHMENT_QUOTA_BYTES", 300 * 1024 * 1024),
  quotaCount: () => intFromEnv("LIME_ATTACHMENT_QUOTA_COUNT", 200),
  perMinute: () => intFromEnv("LIME_RATE_ATTACHMENT_PER_MIN", 240),
};

export const chunkPath = (id: string, n: number) => `a/${id}/${n}`;

/** The chunks already in Storage for an attachment: index to size. */
export async function listChunks(id: string): Promise<Map<number, number>> {
  const { data, error } = await admin().storage.from(BLOB_BUCKET).list(`a/${id}`, { limit: 100 });
  const found = new Map<number, number>();
  if (error) return found;
  for (const object of data ?? []) {
    const n = Number(object.name);
    const size = (object.metadata as { size?: number } | null)?.size;
    if (Number.isInteger(n) && typeof size === "number") found.set(n, size);
  }
  return found;
}
