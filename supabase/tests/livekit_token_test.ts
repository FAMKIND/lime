// LIME-112b: the LiveKit token (pure: no stack needed). `deno test supabase/tests/livekit_token_test.ts`

import { assert, assertEquals } from "jsr:@std/assert@1";
import { IDENTITY_PATTERN, livekitToken, ROOM_PATTERN } from "../functions/_shared/livekit.ts";

const room = "a".repeat(64);
const identity = "0123456789abcdef0123456789abcdef";

function decode(part: string): Record<string, unknown> {
  const padded = part.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (part.length % 4)) % 4);
  return JSON.parse(atob(padded));
}

Deno.test("a token is an HS256 JWT in LiveKit's shape with join, publish, subscribe and data, and nothing admin", async () => {
  const token = await livekitToken("key-1", "secret-1", room, identity, 1_700_000_000_000);
  const [header, claims, signature] = token.split(".");
  assertEquals(decode(header), { alg: "HS256", typ: "JWT" });
  const body = decode(claims) as { iss: string; sub: string; nbf: number; exp: number; video: Record<string, unknown> };
  assertEquals(body.iss, "key-1");
  assertEquals(body.sub, identity, "the identity is the random participant id");
  assertEquals(body.exp, 1_700_000_600, "ten minutes to join");
  assert(body.nbf < 1_700_000_000);
  assertEquals(body.video, { room, roomJoin: true, canPublish: true, canSubscribe: true, canPublishData: true });
  for (const forbidden of ["roomAdmin", "roomCreate", "roomRecord", "ingressAdmin", "hidden", "recorder", "canUpdateOwnMetadata"]) {
    assert(!(forbidden in body.video), `no ${forbidden} grant`);
  }
  // The signature checks with the same secret and not with another.
  const verify = async (secret: string) => {
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
    const raw = atob(signature.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (signature.length % 4)) % 4));
    return crypto.subtle.verify("HMAC", key, Uint8Array.from(raw, (c) => c.charCodeAt(0)), new TextEncoder().encode(`${header}.${claims}`));
  };
  assert(await verify("secret-1"));
  assert(!(await verify("secret-2")));
});

Deno.test("only a 64-hex room and a 16-to-64-hex identity are accepted", () => {
  assert(ROOM_PATTERN.test("0123456789abcdef".repeat(4)));
  for (const bad of ["", "a".repeat(63), "a".repeat(65), "A".repeat(64), "g".repeat(64), `${"a".repeat(63)}\n`, "../".repeat(21) + "a"]) assert(!ROOM_PATTERN.test(bad), bad);
  assert(IDENTITY_PATTERN.test("a".repeat(16)) && IDENTITY_PATTERN.test("a".repeat(64)));
  for (const bad of ["", "a".repeat(15), "a".repeat(65), "user-1", "Z".repeat(32)]) assert(!IDENTITY_PATTERN.test(bad), bad);
});
