// Limits are configuration, not constants: set them as function secrets / environment variables.
// The defaults are the ones decided in LIME-92 (docs/api-v2.md section 11).

function intFromEnv(name: string, fallback: number): number {
  const raw = Deno.env.get(name);
  const value = raw === undefined ? NaN : Number.parseInt(raw, 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

export const config = {
  /** Largest ciphertext per mailbox item, in bytes (blobs come later). */
  maxItemBytes: () => intFromEnv("LIME_MAX_ITEM_BYTES", 64 * 1024),
  /** Recipient-items per minute: per authenticated user, or per access key for sealed sends. */
  sendPerMinute: () => intFromEnv("LIME_RATE_SEND_PER_MIN", 120),
  /** One-time-key claims per minute per user. */
  claimPerMinute: () => intFromEnv("LIME_RATE_CLAIM_PER_MIN", 60),
  /** Directory lookups (exact email) per minute per user. */
  lookupPerMinute: () => intFromEnv("LIME_RATE_LOOKUP_PER_MIN", 30),
  /** Device registrations per hour per user. */
  registerPerHour: () => intFromEnv("LIME_RATE_REGISTER_PER_HOUR", 10),
  /** Guards (implementation limits, not protocol): recipients per send, keys per upload, items per fetch. */
  maxRecipientsPerSend: () => intFromEnv("LIME_MAX_RECIPIENTS_PER_SEND", 500),
  maxKeysPerUpload: () => intFromEnv("LIME_MAX_KEYS_PER_UPLOAD", 100),
  maxItemsPerFetch: () => intFromEnv("LIME_MAX_ITEMS_PER_FETCH", 100),
};
