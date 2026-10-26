// POST account-delete-confirm { token, step: "notices" | "delete" } -> { ok } (LIME-113c). After `account-delete` marked the account "deleting", the phone sends
// its quiet notices and reports it (step "notices"); then it asks for the deletion itself (step "delete"). A wrong token does nothing. If neither comes,
// the sweep finishes the deletion (10 minutes after "notices", else 24 hours after the start).
import { admin, rateLimit, requireUser } from "../_shared/db.ts";
import { sha256Hex } from "../_shared/auth.ts";
import { deleteAccountNow } from "../_shared/accountDeletion.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const userId = await requireUser(req, { allowDeleting: true });
  await rateLimit(`account-delete-confirm:${userId}`, 1, 30, 600);
  const body = await readJson(req, 4096);
  const token = typeof body.token === "string" ? body.token : "";
  const db = admin();
  const { data: row } = await db.from("account_deletions").select("token_hash").eq("user_id", userId).maybeSingle();
  if (!row || !token || row.token_hash !== await sha256Hex(token)) throw new HttpError(403, "forbidden", "Not allowed.");
  if (body.step === "notices") {
    const { error } = await db.from("account_deletions").update({ notices_sent_at: new Date().toISOString() }).eq("user_id", userId);
    if (error) throw new HttpError(500, "internal");
    return json({ ok: true });
  }
  if (body.step === "delete") {
    await deleteAccountNow(userId);
    return json({ ok: true });
  }
  throw new HttpError(400, "bad_request", "Unknown step.");
}));
