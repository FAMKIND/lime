// LIME-111: TURN credentials. Against the LOCAL stack (./supabase/test.sh). The HMAC itself is checked against a value made with openssl.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { call, deleteUser, newUnverifiedUser, newUser } from "./helpers.ts";
import { turnCredentials } from "../functions/_shared/turn.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };

Deno.test("a credential is '<expiry>:<user>' with base64(HMAC-SHA1(secret, username)) and the relay's four addresses", opts, async () => {
  // openssl: printf '1700003600:user-1' | openssl dgst -sha1 -hmac 'test-secret' -binary | base64
  const c = await turnCredentials("test-secret", "user-1", 1_700_000_000_000, "turn.example.org");
  assertEquals(c.username, "1700003600:user-1");
  assertEquals(c.credential, "FhE+Xz5nVcl6gNzpb5pdN6eAe3E=");
  assertEquals(c.ttl, 3600);
  assertEquals(c.urls, [
    "stun:turn.example.org:3478",
    "turn:turn.example.org:3478?transport=udp",
    "turn:turn.example.org:3478?transport=tcp",
    "turns:turn.example.org:5349?transport=tcp",
  ]);
});

Deno.test("turn-credentials needs a fully signed-in session, is rate limited, and says so when calls are not set up", opts, async () => {
  const half = await newUnverifiedUser();
  const me = await newUser();
  try {
    assertEquals((await call("turn-credentials", null, {})).status, 401, "no session");
    assert([401, 403].includes((await call("turn-credentials", half.token, {})).status), "a session that has not finished signing in");
    // This local stack has no TURN secret: it must not invent credentials.
    const first = await call("turn-credentials", me.token, {});
    assert([200, 503].includes(first.status), JSON.stringify(first.body));
    if (first.status === 503) assert(JSON.stringify(first.body).includes("not_configured"), JSON.stringify(first.body));
    if (first.status === 200) assert(first.body.username.includes(me.id) && first.body.credential.length > 10);
    let limited = false;
    for (let i = 0; i < 25 && !limited; i++) limited = (await call("turn-credentials", me.token, {})).status === 429;
    assert(limited, "more than 20 a minute is refused");
  } finally {
    await Promise.all([deleteUser(me), deleteUser(half)]);
  }
});
