// POST avatar { action, ... }: a person's PUBLIC profile photo (LIME-98b, api-v2.md section 6).
//   put        { size }          -> { url }: a signed upload URL for my photo (JPEG, at most 1 MiB).
//   commit     {}                -> verifies the upload, makes the photo visible: { version }.
//   get        { user_id }       -> { url, version }: a signed download URL for their public photo (404 if none).
//   visibility { visibility }    -> "everyone" | "contacts": switching to contacts DELETES the public copy.
//   remove     {}                -> deletes my public photo.
// The photo is plaintext and visible to the server and to any signed-in user who asks for it. A person
// whose visibility is "contacts" has no public photo here (it is an encrypted blob, see `blob`).

import { admin, rateLimit, requireUser } from "../_shared/db.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { AVATAR_BUCKET, blobConfig, MAX_AVATAR_BYTES, objectSize, removeObject, signedDownload, signedUpload } from "../_shared/storage.ts";

const pathOf = (userId: string) => `${userId}.jpg`;

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  const body = await readJson(req);
  await rateLimit(`avatar:${me}`, 1, blobConfig.perMinute(), 60);
  const db = admin();

  switch (body.action) {
    case "put": {
      if (typeof body.size !== "number" || !Number.isInteger(body.size) || body.size < 1 || body.size > MAX_AVATAR_BYTES) {
        throw new HttpError(400, "bad_request", "A photo is at most 1 MB.");
      }
      const { data: profile } = await db.from("profiles").select("user_id").eq("user_id", me).maybeSingle();
      if (!profile) throw new HttpError(409, "no_profile", "Make your profile first.");
      return json({ url: (await signedUpload(AVATAR_BUCKET, pathOf(me))).url });
    }
    case "commit": {
      const size = await objectSize(AVATAR_BUCKET, pathOf(me));
      if (size === null || size < 1) throw new HttpError(409, "not_uploaded", "Upload the photo first.");
      const version = Date.now();
      const { error } = await db.from("profiles").update({ avatar_version: version, photo_visibility: "everyone" }).eq("user_id", me);
      if (error) throw new HttpError(500, "internal");
      return json({ version });
    }
    case "get": {
      if (!isUuid(body.user_id)) throw new HttpError(400, "bad_request", "user_id must be a UUID.");
      const { data } = await db.from("profiles").select("avatar_version, photo_visibility").eq("user_id", body.user_id).maybeSingle();
      if (!data || data.avatar_version === null || data.photo_visibility !== "everyone") {
        throw new HttpError(404, "not_found", "No public photo.");
      }
      return json({ url: await signedDownload(AVATAR_BUCKET, pathOf(body.user_id as string)), version: data.avatar_version });
    }
    case "visibility": {
      if (body.visibility !== "everyone" && body.visibility !== "contacts") {
        throw new HttpError(400, "bad_request", "visibility is everyone or contacts.");
      }
      const update: Record<string, unknown> = { photo_visibility: body.visibility };
      if (body.visibility === "contacts") {
        // Contacts only: the public copy goes away from the server.
        await removeObject(AVATAR_BUCKET, pathOf(me));
        update.avatar_version = null;
      }
      const { error } = await db.from("profiles").update(update).eq("user_id", me);
      if (error) throw new HttpError(500, "internal");
      return json({ visibility: body.visibility });
    }
    case "remove": {
      await removeObject(AVATAR_BUCKET, pathOf(me));
      const { error } = await db.from("profiles").update({ avatar_version: null }).eq("user_id", me);
      if (error) throw new HttpError(500, "internal");
      return json({ ok: true });
    }
    default:
      throw new HttpError(400, "bad_request", "Unknown action.");
  }
}));
