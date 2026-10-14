// LIME-112b: livekit-token on the LOCAL stack (./supabase/test.sh). This stack has no LiveKit secrets, so a valid request is a 503.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { call, deleteUser, newUnverifiedUser, newUser } from "./helpers.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };
const room = "ab".repeat(32);
const participant = "cd".repeat(16);

Deno.test("livekit-token needs a fully signed-in session, validates the room and identity, is rate limited, and says so when calls are not set up", opts, async () => {
  const half = await newUnverifiedUser();
  const me = await newUser();
  try {
    assertEquals((await call("livekit-token", null, { room, participant })).status, 401, "no session");
    assert([401, 403].includes((await call("livekit-token", half.token, { room, participant })).status), "a session that has not finished signing in");
    assertEquals((await call("livekit-token", me.token, { room: "short", participant })).status, 400, "a room that is not 64 hex characters");
    assertEquals((await call("livekit-token", me.token, { room, participant: me.id })).status, 400, "the user id is not an identity");
    assertEquals((await call("livekit-token", me.token, { room })).status, 400, "no identity");
    const ok = await call("livekit-token", me.token, { room, participant });
    assert([200, 503].includes(ok.status), JSON.stringify(ok.body));
    if (ok.status === 503) assert(JSON.stringify(ok.body).includes("not_configured"), JSON.stringify(ok.body));
    if (ok.status === 200) {
      assert(typeof ok.body.token === "string" && ok.body.token.split(".").length === 3 && ok.body.ttl === 600);
      assert(!JSON.stringify(ok.body).includes(me.id), "the user id is nowhere in the answer");
    }
    let limited = false;
    for (let i = 0; i < 25 && !limited; i++) limited = (await call("livekit-token", me.token, { room, participant })).status === 429;
    assert(limited, "more than 20 a minute is refused");
  } finally {
    await Promise.all([deleteUser(me), deleteUser(half)]);
  }
});
