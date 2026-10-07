// POST undelivered-take {}: the hashes (hex SHA-256 of the outer ciphertext) of identified messages
// the caller sent that were never delivered (the recipient's devices were replaced, or the item
// expired after 30 days). Handed over once. The caller matches them against the hashes of what it
// sent, so a message can show "Not delivered". The server learns nothing it did not already hold.

import { admin, requireUser } from "../_shared/db.ts";
import { fromPgBytea, toHex } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req);
  await readJson(req);
  const { data, error } = await admin().rpc("take_undelivered", { p_user: userId });
  if (error) throw new HttpError(500, "internal");
  const hashes = (data as string[] ?? []).map((value) => toHex(fromPgBytea(value)));
  return json({ hashes });
}));
