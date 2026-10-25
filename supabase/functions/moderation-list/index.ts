// POST moderation-list { status?: "open" | "actioned" | "dismissed" } -> { reports: [{ id, kind, reason, urgent, status, created_at }] }
// Moderators only (others: 403). Open reports first, urgent on top. The content is not here: `moderation-open` opens one report.

import { admin } from "../_shared/db.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { requireModerator } from "../_shared/moderation.ts";

Deno.serve(handler(async (req) => {
  await requireModerator(req);
  const body = await readJson(req, 4096);
  const status = typeof body.status === "string" ? body.status : "open";
  if (!["open", "actioned", "dismissed"].includes(status)) throw new HttpError(400, "bad_request", "Unknown status.");
  const { data, error } = await admin().from("moderation_reports").select("id, kind, reason, urgent, status, created_at, resolved_at")
    .eq("status", status).order("urgent", { ascending: false }).order("created_at", { ascending: true }).limit(200);
  if (error) throw new HttpError(500, "internal");
  return json({ reports: data ?? [] });
}));
