// POST keys-upload: a batch of one-time keys for the caller's own device. Returns how many
// unclaimed keys remain, so the client can top the pool up (it uploads 50; it tops up below 20).

import { admin, config, requireDevice, requireUser } from "../_shared/db.ts";
import { fromBase64 } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const body = await readJson(req);
  const device = await requireDevice(userId, body.device_id);

  const keys = body.one_time_keys;
  if (!Array.isArray(keys) || keys.length === 0 || keys.length > config.maxKeysPerUpload()) {
    throw new HttpError(400, "bad_request", `Send 1 to ${config.maxKeysPerUpload()} one-time keys.`);
  }
  const rows = keys.map((entry) => {
    const item = entry as { key_id?: unknown; key?: unknown };
    try {
      if (typeof item.key_id !== "string" || item.key_id.length === 0 || item.key_id.length > 64) throw new Error();
      if (typeof item.key !== "string" || fromBase64(item.key).length !== 32) throw new Error();
    } catch {
      throw new HttpError(400, "bad_request", "Each key needs a key_id and a base64 32-byte key.");
    }
    return { device_id: device.device_id, key_id: item.key_id as string, key: item.key as string };
  });

  const db = admin();
  const { error } = await db.from("one_time_keys").upsert(rows, { onConflict: "device_id,key_id", ignoreDuplicates: true });
  if (error) throw new HttpError(500, "internal");
  const { data: remaining } = await db.rpc("remaining_one_time_keys", { p_device: device.device_id });
  return json({ remaining_one_time_keys: remaining ?? 0 });
}));
