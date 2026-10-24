// POST avatar { action, ... }: a person's PUBLIC profile photo (LIME-98b, api-v2.md section 6).
//   Every action takes an optional `slot`: "photo" (the default), "links" (a JSON list, at most 8 KB) or "background" (a JPEG, at most 1 MiB).
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

// The photo, and (LIME-214, LIME-217) a profile's links and background image: the same actions with a `slot`. Each has its own object, version and
// visibility; the photo's columns keep their old names.
type Slot = { path: (userId: string) => string; version: string; visibility: string; max: number; label: string };
const SLOTS: Record<string, Slot> = {
  photo: { path: (u) => `${u}.jpg`, version: "avatar_version", visibility: "photo_visibility", max: MAX_AVATAR_BYTES, label: "photo" },
  links: { path: (u) => `${u}-links.json`, version: "links_version", visibility: "links_visibility", max: 8 * 1024, label: "list of links" },
  background: { path: (u) => `${u}-background.jpg`, version: "background_version", visibility: "background_visibility", max: MAX_AVATAR_BYTES, label: "background" },
};

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  const body = await readJson(req);
  await rateLimit(`avatar:${me}`, 1, blobConfig.perMinute(), 60);
  const db = admin();
  const slotName = body.slot === undefined ? "photo" : body.slot;
  if (typeof slotName !== "string" || !(slotName in SLOTS)) throw new HttpError(400, "bad_request", "Unknown slot.");
  const slot = SLOTS[slotName];
  const pathOf = slot.path;

  switch (body.action) {
    case "put": {
      if (typeof body.size !== "number" || !Number.isInteger(body.size) || body.size < 1 || body.size > slot.max) {
        throw new HttpError(400, "bad_request", `Your ${slot.label} is too large.`);
      }
      const { data: profile } = await db.from("profiles").select("user_id").eq("user_id", me).maybeSingle();
      if (!profile) throw new HttpError(409, "no_profile", "Make your profile first.");
      return json({ url: (await signedUpload(AVATAR_BUCKET, pathOf(me))).url });
    }
    case "commit": {
      const size = await objectSize(AVATAR_BUCKET, pathOf(me));
      if (size === null || size < 1) throw new HttpError(409, "not_uploaded", "Upload the photo first.");
      const version = Date.now();
      const { error } = await db.from("profiles").update({ [slot.version]: version, [slot.visibility]: "everyone" }).eq("user_id", me);
      if (error) throw new HttpError(500, "internal");
      return json({ version });
    }
    case "get": {
      if (!isUuid(body.user_id)) throw new HttpError(400, "bad_request", "user_id must be a UUID.");
      const { data } = await db.from("profiles").select(`${slot.version}, ${slot.visibility}`).eq("user_id", body.user_id).maybeSingle();
      const row = data as Record<string, unknown> | null;
      if (!row || row[slot.version] === null || row[slot.visibility] !== "everyone") {
        throw new HttpError(404, "not_found", "Nothing public.");
      }
      return json({ url: await signedDownload(AVATAR_BUCKET, pathOf(body.user_id as string)), version: row[slot.version] });
    }
    case "visibility": {
      if (body.visibility !== "everyone" && body.visibility !== "contacts") {
        throw new HttpError(400, "bad_request", "visibility is everyone or contacts.");
      }
      const update: Record<string, unknown> = { [slot.visibility]: body.visibility };
      if (body.visibility === "contacts") {
        // Contacts only: the public copy goes away from the server.
        await removeObject(AVATAR_BUCKET, pathOf(me));
        update[slot.version] = null;
      }
      const { error } = await db.from("profiles").update(update).eq("user_id", me);
      if (error) throw new HttpError(500, "internal");
      return json({ visibility: body.visibility });
    }
    case "remove": {
      await removeObject(AVATAR_BUCKET, pathOf(me));
      const { error } = await db.from("profiles").update({ [slot.version]: null }).eq("user_id", me);
      if (error) throw new HttpError(500, "internal");
      return json({ ok: true });
    }
    default:
      throw new HttpError(400, "bad_request", "Unknown action.");
  }
}));
