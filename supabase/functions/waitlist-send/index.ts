// POST waitlist-send { kind, url, send?, emails?, max? }: sends the ONE launch email (kind "launch") or the ONE Android email (kind "android") to the confirmed rows of that list (LIME-287a).
// Callable only with the service key (Authorization: Bearer <service role key>); nobody else, no session. By default it is a DRY RUN (counts, no mail): `send: true` sends.
// **Idempotent:** a row is picked only while its `sent_at` is empty, and the batch's `sent_at` is written right after Resend accepts it (and Resend's Idempotency-Key drops a repeat of
// the same batch within 24 hours), so a rerun never sends twice. After an Android email its rows are DELETED (the promise: "We've now deleted your address"); launch rows stay until the
// 30-day sweep, or until the person deletes them or moves to the Android list. `emails` limits the run to those addresses (tests); `max` caps one call (the script loops on `remaining`).
// `url` is the store link: https://apps.apple.com/… for launch, https://play.google.com/… for android. Logs nothing identifying.

import { admin } from "../_shared/db.ts";
import { HttpError, handler, json, readJson } from "../_shared/http.ts";
import { functionsUrl } from "../_shared/waitlist.ts";
import { androidEmail, launchEmail, type Mail, sendBatch } from "../_shared/waitlistMail.ts";

const BATCH = 100, DEFAULT_MAX = 500;

function sameBytes(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

function storeUrl(kind: string, value: unknown): string {
  let url: URL;
  try { url = new URL(String(value)); } catch { throw new HttpError(400, "bad_request", "url must be a store link."); }
  const hosts = kind === "launch" ? ["apps.apple.com", "itunes.apple.com"] : ["play.google.com"];
  if (url.protocol !== "https:" || !hosts.includes(url.hostname)) throw new HttpError(400, "bad_request", `url must be an https link on ${hosts.join(" or ")}.`);
  return url.toString();
}

Deno.serve(handler(async (req) => {
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!key || !sameBytes(req.headers.get("authorization") ?? "", `Bearer ${key}`)) throw new HttpError(401, "unauthorized", "The service key is required.");
  const body = await readJson(req, 256 * 1024);
  const kind = body.kind;
  if (kind !== "launch" && kind !== "android") throw new HttpError(400, "bad_request", "kind must be launch or android.");
  const url = storeUrl(kind, body.url);
  const send = body.send === true;
  const max = Math.min(Math.max(Number(body.max) || DEFAULT_MAX, 1), 2000);
  let only: string[] | null = null;
  if (body.emails !== undefined) {
    if (!Array.isArray(body.emails) || body.emails.length === 0 || body.emails.length > 500 || body.emails.some((e) => typeof e !== "string")) throw new HttpError(400, "bad_request", "emails must be a non-empty list.");
    only = (body.emails as string[]).map((e) => e.trim().toLowerCase());
  }

  const db = admin();
  const count = async () => {
    let q = db.from("waitlist").select("*", { count: "exact", head: true }).eq("list", kind).not("confirmed_at", "is", null).is("sent_at", null);
    if (only) q = q.in("email", only);
    const { count: n, error } = await q;
    if (error) throw new HttpError(500, "internal");
    return n ?? 0;
  };
  const eligible = await count();
  if (!send) return json({ kind, dry_run: true, eligible, would_send: Math.min(eligible, max) });

  let sent = 0, failed = false, deleted = 0;
  while (sent < max) {
    let q = db.from("waitlist").select("email, token").eq("list", kind).not("confirmed_at", "is", null).is("sent_at", null).order("created_at").limit(Math.min(BATCH, max - sent));
    if (only) q = q.in("email", only);
    const { data: rows, error } = await q;
    if (error) throw new HttpError(500, "internal");
    if (!rows || rows.length === 0) break;
    const mails: Mail[] = rows.map((r) => kind === "launch"
      ? launchEmail(r.email as string, { appStore: url, android: `${functionsUrl()}/waitlist-android?t=${r.token}`, remove: `${functionsUrl()}/waitlist-unsubscribe?t=${r.token}` })
      : androidEmail(r.email as string, { googlePlay: url }));
    try {
      await sendBatch(mails, kind);
    } catch {
      console.error("waitlist-send: a batch was not accepted; stopping");
      failed = true;
      break;
    }
    const tokens = rows.map((r) => r.token as string);
    if (kind === "launch") {
      const { error: markError } = await db.from("waitlist").update({ sent_at: new Date().toISOString() }).in("token", tokens);
      if (markError) throw new HttpError(500, "internal");
    } else {
      const { error: deleteError } = await db.from("waitlist").delete().in("token", tokens);
      if (deleteError) throw new HttpError(500, "internal");
      deleted += tokens.length;
    }
    sent += rows.length;
    await new Promise((r) => setTimeout(r, 600));   // Resend allows 2 requests a second
  }
  return json({ kind, dry_run: false, sent, deleted, failed, remaining: await count() }, failed ? 502 : 200);
}));
