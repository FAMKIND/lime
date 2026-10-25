// POST moderation-open { id } -> { report: { id, kind, reason, urgent, status, created_at, reporter, payload, readable }, actions: [...] }
// Moderators only. Opens the sealed payload with the moderation key and returns it as the reporter's phone made it: the included item as held, the
// note, the subject's ids. The open is logged (who looked, when).

import { admin } from "../_shared/db.ts";
import { isUuid } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { openReport, requireModerator } from "../_shared/moderation.ts";

Deno.serve(handler(async (req) => {
  const me = await requireModerator(req);
  const body = await readJson(req, 4096);
  if (!isUuid(body.id)) throw new HttpError(400, "bad_request", "id must be a UUID.");
  const db = admin();
  const { data, error } = await db.from("moderation_reports").select("id, kind, reason, urgent, status, created_at, reporter, sealed").eq("id", body.id).maybeSingle();
  if (error) throw new HttpError(500, "internal");
  if (!data) throw new HttpError(404, "not_found", "No such report.");
  const hex = String(data.sealed).replace(/^\\x/, "");
  const sealed = Uint8Array.from(hex.match(/../g) ?? [], (h) => parseInt(h, 16));
  const opened = await openReport(sealed);
  let payload: unknown = null;
  if (opened) {
    try {
      payload = JSON.parse(new TextDecoder().decode(opened));
    } catch {
      payload = null;
    }
  }
  await db.from("moderation_actions").insert({ report_id: data.id, moderator: me, action: "open", target: "" });
  const { data: actions } = await db.from("moderation_actions").select("action, target, note, created_at, moderator").eq("report_id", data.id).neq("action", "open").order("created_at");
  const { sealed: _drop, ...report } = data;
  return json({ report: { ...report, payload, readable: payload !== null }, actions: actions ?? [] });
}));
