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
  /** Public profile reads (other people's display names) per minute per user. */
  profilePerMinute: () => intFromEnv("LIME_RATE_PROFILE_PER_MIN", 120),
  /** Device lists read (`users-devices`) per minute per user: a first send to a big group reads one list per member. */
  deviceListPerMinute: () => intFromEnv("LIME_RATE_DEVICE_LIST_PER_MIN", 120),
  /** Profile edits per minute per user. */
  profileSetPerMinute: () => intFromEnv("LIME_RATE_PROFILE_SET_PER_MIN", 30),
  /** Undelivered-message reports taken (`undelivered-take`) per minute per user. */
  undeliveredPerMinute: () => intFromEnv("LIME_RATE_UNDELIVERED_PER_MIN", 60),
  /** Delivery-key (access proof) uploads per minute per user: registration, a block, a new phone. */
  accessSetPerMinute: () => intFromEnv("LIME_RATE_ACCESS_SET_PER_MIN", 20),
  /** One-time-key uploads per minute per user. */
  keysUploadPerMinute: () => intFromEnv("LIME_RATE_KEYS_UPLOAD_PER_MIN", 30),
  /** Mailbox acknowledgements per minute per user: one after each fetch. */
  ackPerMinute: () => intFromEnv("LIME_RATE_ACK_PER_MIN", 120),
  /** Device registrations per hour per user. */
  registerPerHour: () => intFromEnv("LIME_RATE_REGISTER_PER_HOUR", 10),
  /** Guards (implementation limits, not protocol): recipients per send, keys per upload, items per fetch. */
  maxRecipientsPerSend: () => intFromEnv("LIME_MAX_RECIPIENTS_PER_SEND", 500),
  maxKeysPerUpload: () => intFromEnv("LIME_MAX_KEYS_PER_UPLOAD", 100),
  maxItemsPerFetch: () => intFromEnv("LIME_MAX_ITEMS_PER_FETCH", 100),
};

/** Account-function limits (configuration, like the rest). */
export const accountConfig = {
  /** Identify / sign-in attempts per minute per client address. */
  identifyPerMinute: () => intFromEnv("LIME_RATE_IDENTIFY_PER_MIN", 30),
  signInPerTenMinutes: () => intFromEnv("LIME_RATE_SIGNIN_PER_10MIN", 10),
  /** Setting or changing a password (`signup-set-password`, `password-change-verify`) per ten minutes per user: a person does it once. */
  setPasswordPer10Min: () => intFromEnv("LIME_RATE_SET_PASSWORD_PER_10MIN", 10),
  /** Code checks with no session (`signup-verify`, `reset-verify`) per ten minutes per client address, on top of the five wrong tries per code.
   *  Generous enough for a staff room signing up at once behind one school address. */
  verifyPerAddressPer10Min: () => intFromEnv("LIME_RATE_VERIFY_PER_10MIN", 60),
  /** Emails asked for (sign-up, sign-in code, reset) per hour per address. */
  emailPerHour: () => intFromEnv("LIME_RATE_EMAIL_PER_HOUR", 10),
};
