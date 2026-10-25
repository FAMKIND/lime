// POST moderation-act { report_id?, action, target?, note?, reason? } -> { ok }
// Moderators only; every action is logged in `moderation_actions` (who, when, what). Actions:
//   dismiss          { report_id }              the report is closed, nothing else changes
//   hide_post        { report_id, target: blob id }   jam-blob-get refuses the post's blob from now on (a phone that already has it keeps it)
//   take_down_page   { report_id, target: jam id }    jam-page answers 410 for the page
//   remove_public    { report_id, target: user id, slot: photo|links|background|background_video }   the Everyone object is deleted
//   suspend          { report_id, target: user id, reason }   sign-in and every session call are refused: "This account is suspended"
//   unsuspend        { target: user id }
// Nothing here reaches into anyone's phone: end-to-end encrypted messages and what a phone already holds are out of the server's reach.

import { admin } from "../_shared/db.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { requireModerator } from "../_shared/moderation.ts";
import { AVATAR_BUCKET, removeObject } from "../_shared/storage.ts";

const SLOTS: Record<string, { path: (u: string) => string; version: string }> = {
  photo: { path: (u) => `${u}.jpg`, version: "avatar_version" },
  links: { path: (u) => `${u}-links.json`, version: "links_version" },
  background: { path: (u) => `${u}-background.jpg`, version: "background_version" },
  background_video: { path: (u) => `${u}-background.mp4`, version: "background_video_version" },
};

Deno.serve(handler(async (req) => {
  const me = await requireModerator(req);
  const body = await readJson(req, 8192);
  const db = admin();
  const action = typeof body.action === "string" ? body.action : "";
  const note = typeof body.note === "string" ? body.note.slice(0, 500) : "";
  const reportId = isUuid(body.report_id) ? (body.report_id as string).toLowerCase() : null;
  const target = typeof body.target === "string" ? body.target.toLowerCase() : "";
  const needTarget = () => { if (!isUuid(target)) throw new HttpError(400, "bad_request", "target must be a UUID."); };

  switch (action) {
    case "dismiss":
      break;
    case "hide_post": {
      needTarget();
      const { error } = await db.from("blobs").update({ hidden_at: new Date().toISOString() }).eq("id", target).eq("class", "jam");
      if (error) throw new HttpError(500, "internal");
      break;
    }
    case "take_down_page": {
      needTarget();
      const { error } = await db.from("jams").update({ taken_down_at: new Date().toISOString() }).eq("jam_id", target);
      if (error) throw new HttpError(500, "internal");
      break;
    }
    case "remove_public": {
      needTarget();
      const slot = SLOTS[String(body.slot)];
      if (!slot) throw new HttpError(400, "bad_request", "Unknown slot.");
      await removeObject(AVATAR_BUCKET, slot.path(target));
      const { error } = await db.from("profiles").update({ [slot.version]: null }).eq("user_id", target);
      if (error) throw new HttpError(500, "internal");
      break;
    }
    case "suspend": {
      needTarget();
      const { data: mod } = await db.from("moderators").select("user_id").eq("user_id", target).maybeSingle();
      if (mod) throw new HttpError(409, "moderator", "A moderator cannot be suspended here.");
      const reason = typeof body.reason === "string" ? body.reason.slice(0, 100) : "";
      const { error } = await db.from("account_suspensions").upsert({ user_id: target, reason, created_by: me });
      if (error) throw new HttpError(500, "internal");
      break;
    }
    case "unsuspend": {
      needTarget();
      const { error } = await db.from("account_suspensions").delete().eq("user_id", target);
      if (error) throw new HttpError(500, "internal");
      break;
    }
    default:
      throw new HttpError(400, "bad_request", "Unknown action.");
  }
  await db.from("moderation_actions").insert({ report_id: reportId, moderator: me, action, target, note });
  if (reportId) {
    const { error } = await db.from("moderation_reports").update({
      status: action === "dismiss" ? "dismissed" : "actioned", resolved_at: new Date().toISOString(), resolved_by: me,
    }).eq("id", reportId);
    if (error) throw new HttpError(500, "internal");
  }
  return json({ ok: true });
}));
