// POST turn-credentials {} -> { urls, username, credential, ttl }: time-limited credentials for Lime's TURN relay (LIME-111).
// Only for a fully signed-in session (both sign-in steps); rate-limited. The shared secret lives only here (a function secret,
// `TURN_SECRET`) and on the relay server; it is never sent anywhere. A call's media is end-to-end encrypted between the two
// phones, so the relay only ever carries ciphertext.

import { rateLimit, requireUser } from "../_shared/db.ts";
import { handler, HttpError, json } from "../_shared/http.ts";
import { turnCredentials } from "../_shared/turn.ts";

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  await rateLimit(`turn:${me}`, 1, 20, 60);
  const secret = Deno.env.get("TURN_SECRET");
  if (!secret) throw new HttpError(503, "not_configured", "Calls are not set up on this server yet.");
  return json(await turnCredentials(secret, me, Date.now(), Deno.env.get("TURN_HOST") ?? "turn.limechat.org"));
}));
