// GET mesh-key -> { key_id, fingerprint }: which mesh key pair this server holds (LIME-144). The fingerprint is the first 16 hex characters of
// SHA-256 of the key's PUBLIC half, so a phone can check, once at launch, that the public key it has pinned is the pair of the secret the
// server really uses (a mis-pinned key makes every mesh upload fail with a 403: it happened once). Only for a signed-in session; reveals
// nothing the phone does not already hold (the public key is in the app).

import { rateLimit, requireUser } from "../_shared/db.ts";
import { handler, HttpError, json } from "../_shared/http.ts";
import { meshKeyFingerprint, routingKeysFromEnv } from "../_shared/mesh.ts";

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  await rateLimit(`mesh-key:${me}`, 1, 30, 60);
  const keys = routingKeysFromEnv();
  const current = [...keys.keys()].sort((a, b) => a - b).pop();
  if (current === undefined) throw new HttpError(503, "not_configured", "The mesh is not set up on this server yet.");
  const fingerprint = await meshKeyFingerprint(keys.get(current)!);
  if (!fingerprint) throw new HttpError(500, "internal");
  return json({ key_id: current, fingerprint });
}));
