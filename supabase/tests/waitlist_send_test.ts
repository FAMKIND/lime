// LIME-287a: the launch email, the Android email, and their senders. Local: ./supabase/test.sh. (No Resend key locally: a real send is checked against a stub mail server; the real
// emails are tried on staging with three test addresses.)

import { assert, assertEquals, assertNotEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { admin, ANON_KEY, API_URL, SERVICE_ROLE_KEY } from "./helpers.ts";
import { newToken } from "../functions/_shared/waitlist.ts";
import { androidEmail, confirmEmail, DETECTOR_RESET, launchEmail, sendBatch } from "../functions/_shared/waitlistMail.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };
const fn = (name: string, query = "") => `${API_URL}/functions/v1/${name}${query}`;
const post = (name: string, body: unknown, key = SERVICE_ROLE_KEY) =>
  fetch(fn(name), { method: "POST", headers: { apikey: ANON_KEY, authorization: `Bearer ${key}`, "content-type": "application/json" }, body: JSON.stringify(body) });
const days = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString();
const fresh = () => `ws-${crypto.randomUUID().slice(0, 8)}@example.test`;
const APP = "https://apps.apple.com/app/lime-test", PLAY = "https://play.google.com/store/apps/details?id=test";

async function row(email: string, list: string, extra: Record<string, unknown> = {}) {
  const r = { email, list, token: newToken(), created_at: days(3), confirmed_at: days(2), ...extra };
  const { error } = await admin.from("waitlist").insert(r);
  assert(!error, error?.message);
  return r;
}
const rowsOf = async (email: string) => (await admin.from("waitlist").select("*").eq("email", email)).data ?? [];

Deno.test("waitlist-send answers only to the service key", opts, async () => {
  for (const key of [ANON_KEY, "nope", ""]) {
    const res = await post("waitlist-send", { kind: "launch", url: APP }, key);
    assertEquals(res.status, 401); await res.body?.cancel();
  }
  const noAuth = await fetch(fn("waitlist-send"), { method: "POST", headers: { apikey: ANON_KEY, "content-type": "application/json" }, body: JSON.stringify({ kind: "launch", url: APP }) });
  assertEquals(noAuth.status, 401); await noAuth.body?.cancel();
  const get = await fetch(fn("waitlist-send"), { headers: { apikey: ANON_KEY, authorization: `Bearer ${SERVICE_ROLE_KEY}` } });
  assert(get.status === 405 || get.status === 401); await get.body?.cancel();
});

Deno.test("waitlist-send refuses a bad kind, a bad link and an empty address list; a dry run counts and sends nothing", opts, async () => {
  for (const body of [{ kind: "weekly", url: APP }, { kind: "launch", url: "http://apps.apple.com/x" }, { kind: "launch", url: "https://evil.test/x" }, { kind: "android", url: APP }, { kind: "launch", url: APP, emails: [] }]) {
    const res = await post("waitlist-send", body); assertEquals(res.status, 400, JSON.stringify(body)); await res.body?.cancel();
  }
  const a = await row(fresh(), "launch"), b = await row(fresh(), "launch", { confirmed_at: null }), c = await row(fresh(), "launch", { sent_at: days(1) }), d = await row(fresh(), "android");
  const res = await post("waitlist-send", { kind: "launch", url: APP, emails: [a.email, b.email, c.email, d.email] });
  const j = await res.json();
  assertEquals([res.status, j.dry_run, j.eligible], [200, true, 1]);   // only the confirmed, unsent launch row
  assertEquals((await rowsOf(a.email))[0].sent_at, null);
  await admin.from("waitlist").delete().in("email", [a.email, b.email, c.email, d.email]);
});

Deno.test("a real send with no mail service marks nothing sent and deletes nothing (so a rerun can send)", opts, async () => {
  const a = await row(fresh(), "launch"), b = await row(fresh(), "android");
  const l = await post("waitlist-send", { kind: "launch", url: APP, send: true, emails: [a.email] });
  const lj = await l.json(); assertEquals([l.status, lj.sent, lj.failed], [502, 0, true]);
  const g = await post("waitlist-send", { kind: "android", url: PLAY, send: true, emails: [b.email] });
  const gj = await g.json(); assertEquals([g.status, gj.sent, gj.failed], [502, 0, true]);
  assertEquals((await rowsOf(a.email))[0].sent_at, null);
  assertEquals((await rowsOf(b.email)).length, 1);
  await admin.from("waitlist").delete().in("email", [a.email, b.email]);
});

Deno.test("waitlist-android: a confirmed launch row moves to the Android list and keeps its token; the link is not a way in for anything else", opts, async () => {
  const a = await row(fresh(), "launch", { sent_at: days(1) });
  const res = await fetch(fn("waitlist-android", `?t=${a.token}`), { redirect: "manual", headers: { apikey: ANON_KEY } });
  assertEquals([res.status, res.headers.get("location")], [303, "https://limemessenger.com/android-list/"]); await res.body?.cancel();
  const after = await rowsOf(a.email);
  assertEquals(after.length, 1); assertEquals([after[0].list, after[0].token, after[0].sent_at], ["android", a.token, null]);
  const again = await fetch(fn("waitlist-android", `?t=${a.token}`), { redirect: "manual", headers: { apikey: ANON_KEY } });
  assertEquals(again.status, 303); await again.body?.cancel();   // a second tap changes nothing
  assertEquals((await rowsOf(a.email))[0].list, "android");
  // an unconfirmed row cannot move; an unknown or malformed token is the try-again page
  const u = await row(fresh(), "launch", { confirmed_at: null });
  const un = await fetch(fn("waitlist-android", `?t=${u.token}`), { redirect: "manual", headers: { apikey: ANON_KEY } });
  assertEquals(un.headers.get("location"), "https://limemessenger.com/try-again/"); await un.body?.cancel();
  assertEquals((await rowsOf(u.email))[0].list, "launch");
  const bad = await fetch(fn("waitlist-android", "?t=nope"), { redirect: "manual", headers: { apikey: ANON_KEY } });
  assertEquals(bad.headers.get("location"), "https://limemessenger.com/try-again/"); await bad.body?.cancel();
  await admin.from("waitlist").delete().in("email", [a.email, u.email]);
});

Deno.test("waitlist-android: an address already on the Android list just loses its launch row", opts, async () => {
  const email = fresh();
  const l = await row(email, "launch"), g = await row(email, "android");
  const res = await fetch(fn("waitlist-android", `?t=${l.token}`), { redirect: "manual", headers: { apikey: ANON_KEY } }); await res.body?.cancel();
  const rows = await rowsOf(email);
  assertEquals(rows.map((r) => r.list), ["android"]); assertEquals(rows[0].token, g.token);
  await admin.from("waitlist").delete().eq("email", email);
});

Deno.test("the 30-day sweep deletes launch rows 30 days after their email, and nothing else", opts, async () => {
  const old = await row(fresh(), "launch", { sent_at: days(31) }), young = await row(fresh(), "launch", { sent_at: days(29) }), unsent = await row(fresh(), "launch");
  const android = await row(fresh(), "android", { sent_at: days(40) });
  const swept = await admin.rpc("sweep_waitlist"); assert(!swept.error, swept.error?.message);
  const left = await Promise.all([old, young, unsent, android].map((r) => rowsOf(r.email)));
  assertEquals(left.map((r) => r.length), [0, 1, 1, 1]);
  await admin.from("waitlist").delete().in("email", [young.email, unsent.email, android.email]);
});

Deno.test("the emails say what plot wrote, and each has the iOS data-detector reset", () => {
  const launch = launchEmail("a@x.test", { appStore: APP, android: "https://x.test/a?t=1", remove: "https://x.test/r?t=1" });
  assertEquals(launch.subject, "lime is here");
  for (const piece of ["lime is ready.", "Download it on the App Store", "On Android?", "Tell me when it's on Android", "we'll email you once more", "This is the one email we promised. We'll delete your address in 30 days, or", "delete it now"]) assertStringIncludes(launch.html.replace(/<[^>]+>/g, ""), piece);
  assertStringIncludes(launch.text, APP);
  assertEquals(launch.headers?.["List-Unsubscribe"], "<https://x.test/r?t=1>");
  assertEquals(launch.headers?.["List-Unsubscribe-Post"], "List-Unsubscribe=One-Click");
  const android = androidEmail("a@x.test", { googlePlay: PLAY });
  assertEquals(android.subject, "lime is on Android");
  for (const piece of ["lime is on Android.", "Get it on Google Play", "We've now deleted your address."]) assertStringIncludes(android.html.replace(/<[^>]+>/g, ""), piece);
  const confirm = confirmEmail("https://x.test/c?t=1", "launch");
  for (const html of [launch.html, android.html, confirm.html]) {
    assertStringIncludes(html, "a[x-apple-data-detectors]"); assertStringIncludes(html, "u + #body a"); assertStringIncludes(html, `id="body"`);
    assertStringIncludes(html, "text-decoration: none !important"); assertStringIncludes(html, "date=no");
  }
  assertStringIncludes(DETECTOR_RESET, "color: inherit !important");
  assertStringIncludes(confirm.html, "delete your address in 7 days");
});

Deno.test("sendBatch talks to Resend's batch endpoint with a stable idempotency key", opts, async () => {
  const seen: { path: string; auth: string | null; key: string | null; body: any }[] = [];
  const ac = new AbortController();
  const server = Deno.serve({ port: 0, signal: ac.signal, onListen: () => {} }, async (req) => {
    seen.push({ path: new URL(req.url).pathname, auth: req.headers.get("authorization"), key: req.headers.get("idempotency-key"), body: await req.json() });
    return new Response("{}", { status: 200 });
  });
  Deno.env.set("LIME_NOTIFY_RESEND_API_KEY", "test-key"); Deno.env.set("LIME_NOTIFY_URL", `http://127.0.0.1:${server.addr.port}/emails`);
  try {
    const m1 = launchEmail("a@x.test", { appStore: APP, android: "https://x.test/a", remove: "https://x.test/r" }), m2 = launchEmail("b@x.test", { appStore: APP, android: "https://x.test/a", remove: "https://x.test/r" });
    assertEquals(await sendBatch([m1, m2], "launch"), 2);
    await sendBatch([m2, m1], "launch");   // the same people in another order: the same key
    await sendBatch([m1], "launch");       // fewer people: another key
    assertEquals(seen.map((s) => s.path), ["/emails/batch", "/emails/batch", "/emails/batch"]);
    assertEquals(seen[0].auth, "Bearer test-key");
    assertEquals(seen[0].key, seen[1].key); assertNotEquals(seen[0].key, seen[2].key);
    assertEquals(seen[0].body.map((b: any) => b.to[0]), ["a@x.test", "b@x.test"]);
    assertEquals(seen[0].body[0].subject, "lime is here"); assertStringIncludes(seen[0].body[0].from, "send.limemessenger.com");
    assertEquals(seen[0].body[0].headers["List-Unsubscribe-Post"], "List-Unsubscribe=One-Click");
  } finally {
    ac.abort(); Deno.env.delete("LIME_NOTIFY_RESEND_API_KEY"); Deno.env.delete("LIME_NOTIFY_URL");
  }
});
