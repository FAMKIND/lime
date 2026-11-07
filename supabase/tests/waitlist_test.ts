// LIME-284c2: the launch list. Local: ./supabase/test.sh. The confirm email is not sent here (no Resend key in the local stack); its text is checked directly.

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { admin, ANON_KEY, API_URL } from "./helpers.ts";
import { confirmNotice, isToken, newToken } from "../functions/_shared/waitlist.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };
const fn = (name: string, query = "") => `${API_URL}/functions/v1/${name}${query}`;
const headers = (extra: Record<string, string> = {}) => ({ apikey: ANON_KEY, ...extra });
const form = (fields: Record<string, string>) => new URLSearchParams(fields).toString();

async function join(email: string, list = "launch", accept = "application/json") {
  return await fetch(fn("waitlist-join"), { method: "POST", redirect: "manual", headers: headers({ "content-type": "application/x-www-form-urlencoded", accept }), body: form({ email, list }) });
}
async function rowOf(email: string, list = "launch") {
  const { data, error } = await admin.from("waitlist").select("*").eq("email", email).eq("list", list);
  assert(!error, error?.message);
  return data ?? [];
}
const fresh = () => `wl-${crypto.randomUUID().slice(0, 8)}@example.test`;

Deno.test("join: the same reply twice, one row, nothing but the asked-for fields", opts, async () => {
  const email = fresh();
  const a = await join(email), b = await join(email.toUpperCase());
  const [ja, jb] = [await a.json(), await b.json()];
  assertEquals([a.status, b.status], [200, 200]);
  assertEquals(ja, jb);
  const rows = await rowOf(email);
  assertEquals(rows.length, 1);
  assertEquals(Object.keys(rows[0]).sort(), ["confirmed_at", "created_at", "email", "list", "sent_at", "teaches", "token"]);
  assertEquals(rows[0].confirmed_at, null);
  assert(isToken(rows[0].token));
  await admin.from("waitlist").delete().eq("email", email);
});

Deno.test("join: a plain form post (no JavaScript) is a redirect to the check-your-email page; a bad address and a bad list are refused", opts, async () => {
  const email = fresh();
  const res = await join(email, "launch", "text/html");
  assertEquals(res.status, 303);
  assertEquals(res.headers.get("location"), "https://limemessenger.com/check-email/");
  await res.body?.cancel();
  const bad = await join("not-an-email");
  assertEquals(bad.status, 400); await bad.body?.cancel();
  const badForm = await join("not-an-email", "launch", "text/html");
  assertEquals(badForm.status, 303);
  assertEquals(badForm.headers.get("location"), "https://limemessenger.com/try-again/"); await badForm.body?.cancel();
  const list = await join(fresh(), "newsletter");
  assertEquals(list.status, 400); await list.body?.cancel();
  await admin.from("waitlist").delete().eq("email", email);
});

Deno.test("confirm, the optional tap (changeable), and one-click leave", opts, async () => {
  const email = fresh();
  await (await join(email)).body?.cancel();
  const token = (await rowOf(email))[0].token as string;
  // The tap is for a confirmed address only.
  const early = await fetch(fn("waitlist-teach"), { method: "POST", headers: headers({ "content-type": "application/x-www-form-urlencoded", accept: "application/json" }), body: form({ t: token, v: "k12" }) });
  assertEquals(early.status, 404); await early.body?.cancel();
  const confirm = await fetch(fn("waitlist-confirm", `?t=${token}`), { redirect: "manual", headers: headers() });
  assertEquals(confirm.status, 303);
  assertEquals(confirm.headers.get("location"), `https://limemessenger.com/confirmed/?t=${token}`); await confirm.body?.cancel();
  assert((await rowOf(email))[0].confirmed_at !== null);
  for (const v of ["k12", "higher_ed"]) {
    const tap = await fetch(fn("waitlist-teach"), { method: "POST", headers: headers({ "content-type": "application/x-www-form-urlencoded", accept: "application/json" }), body: form({ t: token, v }) });
    assertEquals(tap.status, 200); await tap.body?.cancel();
    assertEquals((await rowOf(email))[0].teaches, v);
  }
  const wrong = await fetch(fn("waitlist-teach"), { method: "POST", headers: headers({ "content-type": "application/x-www-form-urlencoded", accept: "application/json" }), body: form({ t: token, v: "astronaut" }) });
  assertEquals(wrong.status, 400); await wrong.body?.cancel();
  // Adding the address again after confirming changes nothing (and sends nothing).
  await (await join(email)).body?.cancel();
  assertEquals((await rowOf(email))[0].teaches, "higher_ed");
  const leave = await fetch(fn("waitlist-unsubscribe", `?t=${token}`), { redirect: "manual", headers: headers() });
  assertEquals(leave.status, 303);
  assertEquals(leave.headers.get("location"), "https://limemessenger.com/left/"); await leave.body?.cancel();
  assertEquals((await rowOf(email)).length, 0);
  const again = await fetch(fn("waitlist-unsubscribe", `?t=${token}`), { method: "POST", headers: headers() });
  assertEquals(again.status, 200); await again.body?.cancel();   // the same answer when the row is already gone
});

Deno.test("an unknown or malformed token goes to the try-again page", opts, async () => {
  const res = await fetch(fn("waitlist-confirm", `?t=${newToken()}`), { redirect: "manual", headers: headers() });
  assertEquals([res.status, res.headers.get("location")], [303, "https://limemessenger.com/try-again/"]); await res.body?.cancel();
  const bad = await fetch(fn("waitlist-confirm", "?t=nope"), { redirect: "manual", headers: headers() });
  assertEquals(bad.headers.get("location"), "https://limemessenger.com/try-again/"); await bad.body?.cancel();
});

Deno.test("the same address can be on both lists; the sweep deletes unconfirmed rows after 7 days and nothing else", opts, async () => {
  const email = fresh();
  await (await join(email, "launch")).body?.cancel();
  await (await join(email, "android")).body?.cancel();
  assertEquals((await rowOf(email, "launch")).length + (await rowOf(email, "android")).length, 2);
  const old = fresh(), keep = fresh(), recent = fresh();
  const days = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString();
  const { error } = await admin.from("waitlist").insert([
    { email: old, list: "launch", token: newToken(), created_at: days(8) },
    { email: keep, list: "launch", token: newToken(), created_at: days(30), confirmed_at: days(29) },
    { email: recent, list: "launch", token: newToken(), created_at: days(2) },
  ]);
  assert(!error, error?.message);
  const swept = await admin.rpc("sweep_waitlist");
  assert(!swept.error, swept.error?.message);
  assertEquals([(await rowOf(old)).length, (await rowOf(keep)).length, (await rowOf(recent)).length], [0, 1, 1]);
  await admin.from("waitlist").delete().in("email", [email, keep, recent]);
});

Deno.test("only the service role can read the table", opts, async () => {
  const res = await fetch(`${API_URL}/rest/v1/waitlist?select=email`, { headers: headers({ authorization: `Bearer ${ANON_KEY}` }) });
  assert(res.status === 401 || res.status === 403 || res.status === 404 || (await res.text()) === "[]", `anon read answered ${res.status}`);
});

Deno.test("the confirm email says what the brief says", () => {
  const n = confirmNotice("https://x.test/confirm?t=1", "launch");
  assertEquals(n.subject, "Confirm your email for lime");
  assertStringIncludes(n.text, "we'll email you once, when lime is ready");
  assertStringIncludes(n.text, "Didn't ask for this? Ignore it and we'll delete your address in 7 days.");
  assertStringIncludes(confirmNotice("https://x.test", "android").text, "when lime is on Android");
});
