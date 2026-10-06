// POST keys-claim: atomically claims one one-time key for each active device of a user, so a
// sender can start an Olm session. A key is claimed once. Rate-limited per caller.

import { admin, config, rateLimit, requireUser } from "../_shared/db.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const body = await readJson(req);
  if (!isUuid(body.user_id)) throw new HttpError(400, "bad_request", "user_id must be a UUID.");
  await rateLimit(`claim:${userId}`, 1, config.claimPerMinute(), 60);

  const db = admin();
  const { data: claimed, error } = await db.rpc("claim_one_time_keys_for_user", { p_user: body.user_id });
  if (error) throw new HttpError(500, "internal");
  const { data: devices } = await db
    .from("devices")
    .select("device_id, identity_key, signing_key, master_signature")
    .eq("user_id", body.user_id)
    .is("revoked_at", null);
  const keyByDevice = new Map((claimed ?? []).map((c: { device_id: string; key_id: string | null; key: string | null }) => [c.device_id, c]));
  return json({
    user_id: body.user_id,
    devices: (devices ?? []).map((d) => {
      const k = keyByDevice.get(d.device_id) as { key_id: string | null; key: string | null } | undefined;
      return { ...d, one_time_key: k?.key ? { key_id: k.key_id, key: k.key } : null };
    }),
  });
}));
