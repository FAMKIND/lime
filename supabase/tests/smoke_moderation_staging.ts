// A smoke test of LIME-191 against STAGING (run by ./supabase/smoke-moderation-staging.sh): a throwaway reporter files one report sealed to the staging
// moderation key; a throwaway moderator lists it, opens it (proving the staging secret matches the pinned public key) and dismisses it; a
// takedown is exercised on a throwaway jam page. Everything it made is deleted. One notice email goes to MODERATION_EMAIL (reason "other").

import { assert, assertEquals } from "jsr:@std/assert@1";
import { fromBase64, toBase64 } from "../functions/_shared/bytes.ts";
import { admin, call, deleteUser, newUser } from "./helpers.ts";

// The staging moderation public key, pinned as key id 1 in core/src/client/moderation.rs.
const STAGING_PUBLIC = Deno.env.get("LIME_MODERATION_PUBLIC") ?? "";
assert(STAGING_PUBLIC, "LIME_MODERATION_PUBLIC is not set");

async function seal(payload: unknown, publicB64: string): Promise<string> {
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


const reporter = await newUser();
const moderator = await newUser();
try {
  await admin.from("moderators").insert({ user_id: moderator.id });
  const note = "staging smoke " + crypto.randomUUID();
  const sent = await call("report", reporter.token, { kind: "jam_post", reason: "other", sealed: await seal({ note, included: { text: "smoke" }, subject_ids: ["x"] }, STAGING_PUBLIC) });
  assertEquals(sent.status, 200, "report: " + JSON.stringify(sent.body));
  assertEquals((await call("moderation-list", reporter.token, {})).status, 403, "a normal account is refused");
  const listed = await call("moderation-list", moderator.token, {});
  assertEquals(listed.status, 200, "list: " + JSON.stringify(listed.body));
  const mine = listed.body.reports.find((r: any) => r.reason === "other");
  assert(mine, "the report is in the queue");
  const opened = await call("moderation-open", moderator.token, { id: mine.id });
  assertEquals(opened.status, 200);
  assertEquals(opened.body.report.readable, true, "the staging secret opens what the pinned public key sealed");
  assertEquals(opened.body.report.payload.note, note);
  const acted = await call("moderation-act", moderator.token, { report_id: mine.id, action: "dismiss", note: "smoke" });
  assertEquals(acted.status, 200, "act: " + JSON.stringify(acted.body));
  assertEquals((await call("moderation-list", moderator.token, { status: "dismissed" })).body.reports.some((r: any) => r.id === mine.id), true);
  // A takedown on a throwaway page.
  const jamId = crypto.randomUUID();
  assertEquals((await call("jam-page", reporter.token, { action: "set", jam_id: jamId, title: "Smoke", about: "", topics: [], post_count: 0, subscriber_count: 0 })).status, 200);
  assertEquals((await call("moderation-act", moderator.token, { action: "take_down_page", target: jamId })).status, 200);
  assertEquals((await call("jam-page", moderator.token, { action: "get", jam_id: jamId })).status, 410);
  await admin.from("moderation_reports").delete().eq("reporter", reporter.id);
  console.log("staging moderation smoke test passed: report, list, open (readable), dismiss, take down");
} finally {
  await admin.from("moderation_actions").delete().eq("moderator", moderator.id);
  await admin.from("moderation_reports").delete().eq("reporter", reporter.id);
  await deleteUser(reporter);
  await deleteUser(moderator);
}
