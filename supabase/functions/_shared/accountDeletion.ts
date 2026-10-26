// Deleting an account for good (LIME-113, LIME-113c): Storage objects first, then the one transaction, then the auth user (its rows cascade).
// Safe to repeat. Called by `account-delete-confirm` and by the sweep for an account whose confirm never came.
import { admin } from "./db.ts";
import { sha256Hex } from "./auth.ts";
import { chunkPath, listChunks } from "./attachments.ts";
import { HttpError } from "./http.ts";
import { AVATAR_BUCKET, BLOB_BUCKET, removeObject } from "./storage.ts";

const AVATAR_OBJECTS = (u: string) => [`${u}.jpg`, `${u}-links.json`, `${u}-background.jpg`, `${u}-background.mp4`];

export async function deleteAccountNow(userId: string): Promise<void> {
  const db = admin();
  for (const name of AVATAR_OBJECTS(userId)) await removeObject(AVATAR_BUCKET, name);
  for (let page = 0; page < 20; page++) {
    const { data: blobs } = await db.from("blobs").select("id").eq("owner", userId).limit(500);
    if (!blobs || blobs.length === 0) break;
    for (const row of blobs) {
      await removeObject(BLOB_BUCKET, row.id);
      await db.from("blobs").delete().eq("id", row.id);
    }
  }
  const { data: attachments } = await db.from("attachments").select("id").eq("owner", userId).limit(5000);
  for (const row of attachments ?? []) {
    for (const n of (await listChunks(row.id)).keys()) await removeObject(BLOB_BUCKET, chunkPath(row.id, n));
  }
  const { error: rowsError } = await db.rpc("delete_account_rows", { p_user: userId, p_hash: await sha256Hex(userId) });
  if (rowsError) throw new HttpError(500, "internal");
  const { error: deleteError } = await db.auth.admin.deleteUser(userId);
  if (deleteError) throw new HttpError(500, "internal");
}
