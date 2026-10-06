// POST users-devices: a user's active devices, their identity keys and cross-signatures, and the
// user's master key. Any signed-in user may ask.

import { admin, requireUser } from "../_shared/db.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  await requireUser(req);
  const body = await readJson(req);
  if (!isUuid(body.user_id)) throw new HttpError(400, "bad_request", "user_id must be a UUID.");
  const db = admin();
  const { data: master } = await db.from("master_keys").select("public_key").eq("user_id", body.user_id).maybeSingle();
  const { data: devices, error } = await db
    .from("devices")
    .select("device_id, identity_key, signing_key, master_signature")
    .eq("user_id", body.user_id)
    .is("revoked_at", null)
    .order("created_at");
  if (error) throw new HttpError(500, "internal");
  return json({ user_id: body.user_id, master_key: master?.public_key ?? null, devices: devices ?? [] });
}));
