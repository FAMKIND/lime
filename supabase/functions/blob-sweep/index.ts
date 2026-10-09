// POST blob-sweep: deletes expired attachments and blobs, with their Storage objects (LIME-98c). Called every
// 15 minutes by pg_cron through pg_net with the secret kept in `sweep_target`; refused without it. It deletes
// nothing that has not expired, so a stray call is harmless.

import { admin } from "../_shared/db.ts";
import { handler, HttpError, json } from "../_shared/http.ts";
import { BLOB_BUCKET, removeObject } from "../_shared/storage.ts";
import { chunkPath } from "../_shared/attachments.ts";

function sameText(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

Deno.serve(handler(async (req) => {
  if (req.method !== "POST") throw new HttpError(405, "method_not_allowed", "Use POST.");
  const db = admin();
  const { data: target } = await db.from("sweep_target").select("secret").eq("id", 1).maybeSingle();
  const presented = req.headers.get("x-sweep-secret") ?? "";
  if (!target || !sameText(presented, target.secret)) throw new HttpError(401, "unauthorized", "Not allowed.");

  const now = new Date().toISOString();
  const dayAgo = new Date(Date.now() - 86_400_000).toISOString();
  let attachments = 0;
  let blobs = 0;

  // Attachments past their expiry, or never completed within a day.
  const { data: stale } = await db.from("attachments").select("id, chunks")
    .or(`expires_at.lt.${now},and(committed_at.is.null,created_at.lt.${dayAgo})`).limit(200);
  for (const row of stale ?? []) {
    for (let n = 0; n < row.chunks; n++) await removeObject(BLOB_BUCKET, chunkPath(row.id, n));
    await db.from("attachments").delete().eq("id", row.id);
    attachments++;
  }
  // Blobs (LIME-98b) with an expiry that has passed (profile photos have none).
  const { data: old } = await db.from("blobs").select("id").lt("expires_at", now).limit(200);
  for (const row of old ?? []) {
    await removeObject(BLOB_BUCKET, row.id);
    await db.from("blobs").delete().eq("id", row.id);
    blobs++;
  }
  return json({ attachments, blobs });
}));
