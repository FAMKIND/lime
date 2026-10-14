// POST livekit-token { room, participant } -> { url, token, ttl }: a short-lived token for Lime's LiveKit server (LIME-112b).
// Only for a fully signed-in session; 20 a minute. `room` is the call's random id (64 hex characters; holding it is the capability),
// `participant` is a random per-call identity chosen by the app (never the user id). The token allows join, publish, subscribe and
// data, and nothing else (no admin, no recording), for ten minutes to join. Nothing is stored and the room is never logged. The media
// is end-to-end encrypted by the phones, so the server only ever forwards ciphertext. 503 not_configured until the secrets exist.

import { rateLimit, requireUser } from "../_shared/db.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { IDENTITY_PATTERN, LIVEKIT_JOIN_TTL_SECONDS, livekitToken, ROOM_PATTERN } from "../_shared/livekit.ts";

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  await rateLimit(`livekit:${me}`, 1, 20, 60);
  const body = await readJson(req, 1024);
  const room = body.room;
  const participant = body.participant;
  if (typeof room !== "string" || !ROOM_PATTERN.test(room)) throw new HttpError(400, "bad_request", "The room must be 64 hex characters.");
  if (typeof participant !== "string" || !IDENTITY_PATTERN.test(participant)) throw new HttpError(400, "bad_request", "The participant must be 16 to 64 hex characters.");
  const key = Deno.env.get("LIVEKIT_API_KEY");
  const secret = Deno.env.get("LIVEKIT_API_SECRET");
  const url = Deno.env.get("LIVEKIT_URL");
  if (!key || !secret || !url) throw new HttpError(503, "not_configured", "Group calls are not set up on this server yet.");
  return json({ url, token: await livekitToken(key, secret, room, participant, Date.now()), ttl: LIVEKIT_JOIN_TTL_SECONDS });
}));
