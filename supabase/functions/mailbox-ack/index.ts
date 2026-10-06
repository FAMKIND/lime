// POST mailbox-ack: deletes the caller's items up to and including a cursor.

import { admin, requireDevice, requireUser } from "../_shared/db.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const body = await readJson(req);
  const device = await requireDevice(userId, body.device_id);
  const upTo = Number(body.up_to_cursor);
  if (!Number.isInteger(upTo) || upTo < 0) throw new HttpError(400, "bad_request", "up_to_cursor must be a cursor (a whole number).");
  const { data, error } = await admin()
    .from("mailbox_items")
    .delete()
    .eq("to_device", device.device_id)
    .lte("cursor", upTo)
    .select("cursor");
  if (error) throw new HttpError(500, "internal");
  return json({ deleted: (data ?? []).length });
}));
