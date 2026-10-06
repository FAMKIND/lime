// POST mailbox-fetch: the items after a cursor for the caller's own device, oldest first.

import { admin, config, requireDevice, requireUser } from "../_shared/db.ts";
import { fromPgBytea, toBase64 } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  const body = await readJson(req);
  const device = await requireDevice(userId, body.device_id);
  const after = body.after === undefined ? 0 : Number(body.after);
  if (!Number.isInteger(after) || after < 0) throw new HttpError(400, "bad_request", "after must be a cursor (a whole number).");
  const maxItems = config.maxItemsPerFetch();
  const requested = body.limit === undefined ? maxItems : Number(body.limit);
  const limit = Number.isInteger(requested) && requested > 0 ? Math.min(requested, maxItems) : maxItems;

  const { data, error } = await admin()
    .from("mailbox_items")
    .select("cursor, ciphertext, size, received_at, identified, sender_user")
    .eq("to_device", device.device_id)
    .gt("cursor", after)
    .order("cursor", { ascending: true })
    .limit(limit + 1);
  if (error) throw new HttpError(500, "internal");
  const rows = data ?? [];
  const items = rows.slice(0, limit).map((r) => ({
    cursor: r.cursor,
    ciphertext: toBase64(fromPgBytea(r.ciphertext as string)),
    size: r.size,
    received_at: r.received_at,
    // Only an identified send (a stranger's first message) carries a sender; a sealed one never does.
    ...(r.identified ? { identified: true, sender_user: r.sender_user } : {}),
  }));
  return json({ items, has_more: rows.length > limit });
}));
