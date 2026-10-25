// LIME-191: reports, the moderation queue and the takedowns. Against the LOCAL stack: ./supabase/test.sh
// The reporter's side (sealing to the moderation key) is done here in TypeScript, the same construction as lime_core's `moderation::seal_report`.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { fromBase64, toBase64 } from "../functions/_shared/bytes.ts";
import { admin, ANON_KEY, API_URL, call, deleteUser, newUser, randomBytes, type TestUser } from "./helpers.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };
// The LOCAL test moderation key's public half (its secret is in supabase/functions/.env).
const LOCAL_MODERATION_PUBLIC = "upje5wDr05+7JLNK6ww6T2eg2/oS5IX3ts4BYAduKyM=";

async function seal(payload: unknown, publicB64 = LOCAL_MODERATION_PUBLIC): Promise<string> {
  const pair = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"]) as CryptoKeyPair;
  const ephemeral = new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey));
  const server = await crypto.subtle.importKey("raw", fromBase64(publicB64) as BufferSource, { name: "X25519" }, false, []);
  const shared = new Uint8Array(await crypto.subtle.deriveBits({ name: "X25519", public: server }, pair.privateKey, 256));
  const hkdf = await crypto.subtle.importKey("raw", shared as BufferSource, "HKDF", false, ["deriveBits"]);
  const info = new Uint8Array([...new TextEncoder().encode("lime-report-v1"), 1, ...ephemeral]);
  const okm = new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: info as BufferSource }, hkdf, 44 * 8));
  const aes = await crypto.subtle.importKey("raw", okm.slice(0, 32) as BufferSource, "AES-GCM", false, ["encrypt"]);
  const aad = new Uint8Array([1, ...ephemeral]);
  const plaintext = new TextEncoder().encode(JSON.stringify(payload));
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: okm.slice(32, 44) as BufferSource, additionalData: aad as BufferSource }, aes, plaintext as BufferSource));
  return toBase64(new Uint8Array([...aad, ...sealed]));
}

async function withUsers<T>(count: number, fn: (users: TestUser[]) => Promise<T>): Promise<T> {
  const users = await Promise.all(Array.from({ length: count }, newUser));
  try {
    return await fn(users);
  } finally {
    await Promise.all(users.map(deleteUser));
  }
}

async function putBytes(url: string, bytes: Uint8Array): Promise<number> {
  const res = await fetch(API_URL + url, { method: "PUT", headers: { "content-type": "application/octet-stream", apikey: ANON_KEY }, body: bytes as unknown as BodyInit });
  await res.body?.cancel();
  return res.status;
}

async function uploadPost(user: TestUser, jamId: string): Promise<string> {
  const id = crypto.randomUUID();
  const bytes = randomBytes(2000);
  const started = await call("blob", user.token, { action: "put", blob_id: id, size: bytes.length, class: "jam", jam_id: jamId });
  assertEquals(started.status, 200, JSON.stringify(started.body));
  assertEquals(await putBytes(started.body.url, bytes), 200);
  assertEquals((await call("blob", user.token, { action: "commit", blob_id: id })).status, 200);
  return id;
}

async function report(user: TestUser, reason: string, payload: unknown = { note: "x" }) {
  return await call("report", user.token, { kind: "jam_post", reason, sealed: await seal(payload) });
}

Deno.test("a report is stored sealed, needs a session and a known reason, and is limited to 10 a day", opts, async () => {
  await withUsers(1, async ([reporter]) => {
    assertEquals((await call("report", null, { kind: "jam_post", reason: "spam", sealed: await seal({}) })).status, 401);
    assertEquals((await call("report", reporter.token, { kind: "jam_post", reason: "nope", sealed: await seal({}) })).status, 400);
    assertEquals((await call("report", reporter.token, { kind: "wat", reason: "spam", sealed: await seal({}) })).status, 400);
    assertEquals((await call("report", reporter.token, { kind: "jam_post", reason: "spam", sealed: "AAAA" })).status, 400, "too short to be a sealed report");
    const sent = await report(reporter, "spam", { note: "buy my stuff" });
    assertEquals(sent.status, 200, JSON.stringify(sent.body));
    const { data } = await admin.from("moderation_reports").select("sealed, kind, reason, urgent, status").eq("reporter", reporter.id);
    assertEquals([data![0].kind, data![0].reason, data![0].urgent, data![0].status], ["jam_post", "spam", false, "open"]);
    assert(!String(data![0].sealed).includes("buy"), "the note is not in the row in the clear");
    for (let i = 0; i < 6; i++) assertEquals((await report(reporter, "spam")).status, 200);   // 4 calls so far count too (the limit is taken first)
    assertEquals((await report(reporter, "spam")).status, 429, "10 a day");
    await admin.from("moderation_reports").delete().eq("reporter", reporter.id);
  });
});

Deno.test("only a moderator lists or opens reports; the queue puts child safety on top; opening shows the payload", opts, async () => {
  await withUsers(3, async ([reporter, moderator, other]) => {
    await admin.from("moderators").insert({ user_id: moderator.id });
    assertEquals((await report(reporter, "spam", { n: 1 })).status, 200);
    assertEquals((await report(reporter, "child_safety", { n: 2, included: "a message" })).status, 200);
    assertEquals((await call("moderation-list", other.token, {})).status, 403, "not on the list");
    assertEquals((await call("moderation-list", null, {})).status, 401);
    const listed = await call("moderation-list", moderator.token, {});
    assertEquals(listed.status, 200, JSON.stringify(listed.body));
    const mine = listed.body.reports.filter((r: any) => ["spam", "child_safety"].includes(r.reason));
    assertEquals(mine[0].reason, "child_safety", "urgent first");
    assertEquals(mine[0].urgent, true);
    assertEquals((await call("moderation-open", other.token, { id: mine[0].id })).status, 403);
    const opened = await call("moderation-open", moderator.token, { id: mine[0].id });
    assertEquals(opened.status, 200, JSON.stringify(opened.body));
    assertEquals(opened.body.report.payload, { n: 2, included: "a message" });
    assertEquals(opened.body.report.reporter, reporter.id);
    const { data: logged } = await admin.from("moderation_actions").select("action, moderator").eq("report_id", mine[0].id);
    assertEquals(logged!.map((a) => a.action), ["open"], "who looked is logged");
    // A report sealed to some other key cannot be opened.
    const stranger = await crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"]) as CryptoKeyPair;
    const strangerPublic = toBase64(new Uint8Array(await crypto.subtle.exportKey("raw", stranger.publicKey)));
    await call("report", reporter.token, { kind: "person", reason: "other", sealed: await seal({ z: 1 }, strangerPublic) });
    const again = await call("moderation-list", moderator.token, {});
    const odd = again.body.reports.find((r: any) => r.kind === "person");
    const unreadable = await call("moderation-open", moderator.token, { id: odd.id });
    assertEquals(unreadable.body.report.readable, false);
    await admin.from("moderation_reports").delete().eq("reporter", reporter.id);
  });
});

Deno.test("hide a post, take a page down, remove a public picture, suspend and lift: each is logged and works", opts, async () => {
  await withUsers(3, async ([writer, moderator, reader]) => {
    await admin.from("moderators").insert({ user_id: moderator.id });
    const jamId = crypto.randomUUID();
    assertEquals((await call("jam-page", writer.token, { action: "set", jam_id: jamId, title: "Maths", about: "", topics: [], post_count: 1, subscriber_count: 0 })).status, 200);
    const blobId = await uploadPost(writer, jamId);
    assertEquals((await call("jam-blob-get", null, { blob_id: blobId })).status, 200);
    assertEquals((await report(reader, "spam", { post: blobId })).status, 200);
    const id = (await call("moderation-list", moderator.token, {})).body.reports[0].id;

    assertEquals((await call("moderation-act", reader.token, { action: "hide_post", target: blobId })).status, 403);
    assertEquals((await call("moderation-act", moderator.token, { report_id: id, action: "hide_post", target: blobId, note: "spam" })).status, 200);
    assertEquals((await call("jam-blob-get", null, { blob_id: blobId })).status, 404, "a hidden post is gone for new fetches");
    const { data: rep } = await admin.from("moderation_reports").select("status, resolved_by").eq("id", id).single();
    assertEquals([rep!.status, rep!.resolved_by], ["actioned", moderator.id]);

    assertEquals((await call("jam-page", reader.token, { action: "get", jam_id: jamId })).status, 200);
    assertEquals((await call("moderation-act", moderator.token, { action: "take_down_page", target: jamId })).status, 200);
    assertEquals((await call("jam-page", reader.token, { action: "get", jam_id: jamId })).status, 410);
    assertEquals((await call("jam-page", reader.token, { action: "by_writer", writer_id: writer.id })).body.jam, null);

    await admin.from("profiles").insert({ user_id: writer.id, display_name: "W", background_version: 7, background_visibility: "everyone" });
    assertEquals((await call("moderation-act", moderator.token, { action: "remove_public", target: writer.id, slot: "background" })).status, 200);
    const { data: prof } = await admin.from("profiles").select("background_version").eq("user_id", writer.id).single();
    assertEquals(prof!.background_version, null);

    assertEquals((await call("moderation-act", moderator.token, { action: "suspend", target: moderator.id, reason: "x" })).status, 409, "not a moderator");
    assertEquals((await call("moderation-act", moderator.token, { action: "suspend", target: reader.id, reason: "abuse" })).status, 200);
    const refused = await call("report", reader.token, { kind: "person", reason: "spam", sealed: await seal({}) });
    assertEquals([refused.status, refused.body.error], [403, "suspended"]);
    assertEquals((await call("moderation-act", moderator.token, { action: "unsuspend", target: reader.id })).status, 200);
    assertEquals((await report(reader, "spam")).status, 200);

    const { data: log } = await admin.from("moderation_actions").select("action").eq("moderator", moderator.id).neq("action", "open");
    assertEquals(log!.map((a) => a.action).sort(), ["hide_post", "remove_public", "suspend", "take_down_page", "unsuspend"].sort());
    await admin.from("moderation_reports").delete().eq("reporter", reader.id);
  });
});

Deno.test("a dismissed report closes, and the sweep deletes resolved reports 180 days later", opts, async () => {
  await withUsers(2, async ([reporter, moderator]) => {
    await admin.from("moderators").insert({ user_id: moderator.id });
    assertEquals((await report(reporter, "other")).status, 200);
    const id = (await call("moderation-list", moderator.token, {})).body.reports.find((r: any) => r.reason === "other").id;
    assertEquals((await call("moderation-act", moderator.token, { report_id: id, action: "dismiss" })).status, 200);
    assertEquals((await call("moderation-list", moderator.token, { status: "dismissed" })).body.reports.some((r: any) => r.id === id), true);
    await admin.from("moderation_reports").update({ resolved_at: new Date(Date.now() - 181 * 86400000).toISOString() }).eq("id", id);
    await admin.rpc("sweep_moderation");
    const { data } = await admin.from("moderation_reports").select("id").eq("id", id);
    assertEquals(data!.length, 0);
  });
});
