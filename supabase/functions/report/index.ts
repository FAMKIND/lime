// POST report { kind, reason, sealed } -> { ok }: a report of someone or something (LIME-191, App Store rule 1.2).
// `sealed` is base64 of the payload sealed on the reporter's phone to the moderation key (the included item, the note, the subject's ids): this function
// cannot read it. It learns the reporter (the session), the kind of subject, the reason; 10 a day per reporter; size-capped.
// Nothing here logs the sealed bytes or the ids.

import { admin, rateLimit, requireUser } from "../_shared/db.ts";
import { fromBase64 } from "../_shared/bytes.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { KINDS, MAX_SEALED_BYTES, notifyModerators, REASONS } from "../_shared/moderation.ts";

Deno.serve(handler(async (req) => {
  const me = await requireUser(req);
  const body = await readJson(req, 160 * 1024);
  await rateLimit(`report:${me}`, 1, 10, 86400);
  if (typeof body.kind !== "string" || !KINDS.includes(body.kind) || typeof body.reason !== "string" || !REASONS.includes(body.reason)) {
    throw new HttpError(400, "bad_request", "Unknown kind or reason.");
  }
  let sealed: Uint8Array;
  try {
    sealed = fromBase64(String(body.sealed ?? ""));
  } catch {
    throw new HttpError(400, "bad_request", "sealed must be base64.");
  }
  if (sealed.length < 50 || sealed.length > MAX_SEALED_BYTES) throw new HttpError(400, "bad_request", "That report is empty or too large.");
  const urgent = body.reason === "child_safety";
  // bytea over PostgREST: the "\x" hex form.
  const hex = "\\x" + Array.from(sealed, (b) => b.toString(16).padStart(2, "0")).join("");
  const { error } = await admin().from("moderation_reports").insert({ reporter: me, kind: body.kind, reason: body.reason, urgent, sealed: hex });
  if (error) throw new HttpError(500, "internal");
  await notifyModerators(body.reason, urgent);
  return json({ ok: true });
}));
