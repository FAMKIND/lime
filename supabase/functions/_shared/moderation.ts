// Reports and moderation (LIME-191, docs/moderation.md). A report is sealed on the reporter's phone to the server's MODERATION key (a key pair of its
// own, not the mesh key): only `moderation-open` opens it, and only for an account in `moderators`.

import { admin, requireUser } from "./db.ts";
import { HttpError } from "./http.ts";
import { openSealed } from "./mesh.ts";

export const REPORT_LABEL = new TextEncoder().encode("lime-report-v1");
export const REASONS = ["harassment", "spam", "impersonation", "inappropriate", "child_safety", "hate_violence", "other"];
export const KINDS = ["message", "person", "group", "jam_post", "comment", "jam", "org", "profile_item"];
export const MAX_SEALED_BYTES = 96 * 1024;

/** The moderation secret keys by key id (today one: id 1, from `MODERATION_SECRET_KEY`, base64 of the 32-byte X25519 secret). */
export function moderationKeysFromEnv(): Map<number, string> {
  const keys = new Map<number, string>();
  const first = Deno.env.get("MODERATION_SECRET_KEY");
  if (first) keys.set(1, first);
  return keys;
}

export async function openReport(sealed: Uint8Array): Promise<Uint8Array | null> {
  return await openSealed(moderationKeysFromEnv(), sealed, REPORT_LABEL);
}

/** A verified session that is on the allow-list. Anyone else gets the same plain 403, so the list is not probeable beyond "not you". */
export async function requireModerator(req: Request): Promise<string> {
  const me = await requireUser(req);
  const { data, error } = await admin().from("moderators").select("user_id").eq("user_id", me).maybeSingle();
  if (error) throw new HttpError(500, "internal");
  if (!data) throw new HttpError(403, "forbidden", "Not allowed.");
  return me;
}

/** Tells the moderators' address that a report arrived: the reason only, never the content ("URGENT" for a child's safety). Best effort. */
export async function notifyModerators(reason: string, urgent: boolean): Promise<void> {
  const to = Deno.env.get("MODERATION_EMAIL");
  // The same Resend key and sender as the account notices (LIME_NOTIFY_*), unless moderation has its own.
  const key = Deno.env.get("RESEND_API_KEY") ?? Deno.env.get("LIME_NOTIFY_RESEND_API_KEY");
  if (!to || !key) return;
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
      body: JSON.stringify({
        from: Deno.env.get("MODERATION_FROM") ?? Deno.env.get("LIME_NOTIFY_FROM") ?? "lime <reports@limemessenger.org>", to: [to],
        subject: `${urgent ? "URGENT: " : ""}lime report: ${reason.replace("_", " ")}`,
        text: "A new report is waiting in Settings > Moderation. The report's content is not in this email.",
      }),
    });
    await res.body?.cancel();
  } catch {
    // The report is saved either way.
  }
}
