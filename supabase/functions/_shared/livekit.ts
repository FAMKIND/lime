// Access tokens for Lime's LiveKit server (LIME-112b). A token is a short HS256 JWT in LiveKit's format: it names a room and an identity
// and grants joining, publishing, subscribing and data; never room admin, never recording. The room is the call's random id (holding it
// is the capability to ask for a token: there is no server-side group membership, architecture section 5), and the identity is a random
// per-call id the app makes up, never the user id. Nothing here is stored or logged.

export const LIVEKIT_JOIN_TTL_SECONDS = 600;

/** The call's random id: 32 random bytes as hex. */
export const ROOM_PATTERN = /^[0-9a-f]{64}$/;
/** A random per-call participant id: 8 to 32 random bytes as hex. */
export const IDENTITY_PATTERN = /^[0-9a-f]{16,64}$/;

function base64url(bytes: Uint8Array | string): string {
  const data = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const byte of data) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function livekitToken(
  apiKey: string, apiSecret: string, room: string, identity: string, nowMs: number, ttl = LIVEKIT_JOIN_TTL_SECONDS,
): Promise<string> {
  const now = Math.floor(nowMs / 1000);
  const header = base64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: apiKey,
    sub: identity,
    nbf: now - 10,
    iat: now,
    exp: now + ttl,
    video: { room, roomJoin: true, canPublish: true, canSubscribe: true, canPublishData: true },
  }));
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(apiSecret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${header}.${claims}`)));
  return `${header}.${claims}.${base64url(mac)}`;
}
