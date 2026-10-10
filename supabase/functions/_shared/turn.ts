// TURN credentials for calls (LIME-111): the coturn "REST API" shared-secret scheme. The username is "<expiry>:<user>" and the
// password is base64(HMAC-SHA1(secret, username)). coturn (`use-auth-secret`) checks them without any list of users, so the relay
// learns nothing about who calls whom beyond the opaque user id inside the username, and a credential stops working at its expiry.

export const TURN_TTL_SECONDS = 3600;

export type TurnCredentials = { urls: string[]; username: string; credential: string; ttl: number };

export async function turnCredentials(secret: string, user: string, nowMs: number, host: string, ttl = TURN_TTL_SECONDS): Promise<TurnCredentials> {
  const username = `${Math.floor(nowMs / 1000) + ttl}:${user}`;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(username)));
  let binary = "";
  for (const byte of mac) binary += String.fromCharCode(byte);
  return {
    urls: [
      `stun:${host}:3478`,
      `turn:${host}:3478?transport=udp`,
      `turn:${host}:3478?transport=tcp`,
      `turns:${host}:5349?transport=tcp`,
    ],
    username,
    credential: btoa(binary),
    ttl,
  };
}
