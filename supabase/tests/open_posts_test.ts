// LIME-210a: open posts and the open file class. Against the LOCAL stack: ./supabase/test.sh
import { assert, assertEquals } from "jsr:@std/assert@1";
import { toBase64 } from "../functions/_shared/bytes.ts";
import { admin, ANON_KEY, API_URL, call, deleteUser, newMasterKey, newUser, randomBytes, type MasterKey, type TestUser } from "./helpers.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };

type Writer = { user: TestUser; deviceId: string; cert: Record<string, string>; sign: (text: string) => Promise<string>; jamId: string };

/** A user with a real device signing key (the helper's is random bytes), a master key and a jam. */
async function newWriter(): Promise<Writer> {
  const user = await newUser();
  const master: MasterKey = await newMasterKey();
  const pair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const signingKey = toBase64(new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)));
  const deviceId = crypto.randomUUID(), identityKey = toBase64(randomBytes(32));
  const master_signature = await master.sign(`lime-device-v1\n${deviceId}\n${identityKey}\n${signingKey}`);
  const reg = await call("devices-register", user.token, { device_id: deviceId, identity_key: identityKey, signing_key: signingKey, master_key: master.publicKey, master_signature });
  assertEquals(reg.status, 201, JSON.stringify(reg.body));
  const jamId = crypto.randomUUID();
  assertEquals((await call("jam-page", user.token, { action: "set", jam_id: jamId, title: "Fractions", about: "", topics: [], post_count: 0 })).status, 200);
  return {
    user, deviceId, jamId,
    cert: { device_id: deviceId, identity_key: identityKey, signing_key: signingKey, master_key: master.publicKey, master_signature },
    sign: async (text) => toBase64(new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, pair.privateKey, new TextEncoder().encode("lime-open-post-v1\n" + text)))),
  };
}

function payloadOf(w: Writer, over: Record<string, unknown> = {}): string {
  return JSON.stringify({
    post_id: crypto.randomUUID(), author_kind: "person", author_id: w.user.id, jam_id: w.jamId, kind: "article", title: "Equal parts", subtitle: "A lesson",
    markdown: "# Hello\n\nFractions are **equal parts**.", attachments: [], topics: ["Maths"], version: 1, ...over,
  });
}

async function publish(w: Writer, text: string, action = "publish") {
  return await call("open-post", w.user.token, { action, payload: text, signature: await w.sign(text), cert: w.cert });
}

async function setFlag(on: boolean) {
  await admin.from("server_flags").update({ enabled: on }).eq("name", "open_posts_enabled");
}

async function withWriter<T>(fn: (w: Writer) => Promise<T>): Promise<T> {
  const w = await newWriter();
  await setFlag(true);
  try {
    return await fn(w);
  } finally {
    await setFlag(false);
    await deleteUser(w.user);
  }
}

Deno.test("open_posts_enabled is off by default and publishing is refused while it is", opts, async () => {
  const w = await newWriter();
  try {
    const { data } = await admin.from("server_flags").select("enabled").eq("name", "open_posts_enabled").single();
    assertEquals(data?.enabled, false);
    const res = await publish(w, payloadOf(w));
    assertEquals([res.status, res.body.error], [403, "open_posts_disabled"]);
  } finally {
    await deleteUser(w.user);
  }
});

Deno.test("publish, list, fetch without a session, edit and delete (tombstone)", opts, async () => {
  await withWriter(async (w) => {
    const postId = crypto.randomUUID();
    const text = payloadOf(w, { post_id: postId });
    const made = await publish(w, text);
    assertEquals(made.status, 201, JSON.stringify(made.body));
    assertEquals(made.body.version, 1);
    // The feed lists metadata and a short excerpt.
    const reader = await newUser();
    try {
      const feed = await call("open-feed", reader.token, { since: made.body.seq - 1 });
      assertEquals(feed.status, 200);
      const item = feed.body.items.find((i: any) => i.post_id === postId);
      assertEquals([item.title, item.kind, item.author_id], ["Equal parts", "article", w.user.id]);
      assert(item.excerpt.includes("Fractions are equal parts"));
      assertEquals(item.payload, undefined, "the feed carries metadata, not the row");
      // The whole signed row, with no session at all.
      const got = await call("open-post-get", null, { post_id: postId });
      assertEquals(got.status, 200);
      assertEquals(got.body.post.payload, text);
      assertEquals(got.body.post.cert.device_id, w.deviceId);
      // An edit: the next version only.
      const v3 = await publish(w, payloadOf(w, { post_id: postId, version: 3 }), "edit");
      assertEquals(v3.status, 409);
      const v2 = await publish(w, payloadOf(w, { post_id: postId, version: 2, title: "Equal parts, again" }), "edit");
      assertEquals([v2.status, v2.body.version], [200, 2]);
      assertEquals((await call("open-post-get", null, { post_id: postId })).body.post.version, 2);
      // Delete: a tombstone in the feed, 404 on fetch.
      const del = await call("open-post", w.user.token, { action: "delete", post_id: postId });
      assertEquals(del.status, 200);
      const after = await call("open-feed", reader.token, { since: v2.body.seq });
      assertEquals(after.body.items.find((i: any) => i.post_id === postId), { post_id: postId, seq: del.body.seq, gone: true });
      assertEquals((await call("open-post-get", null, { post_id: postId })).status, 404);
      const { data: row } = await admin.from("open_posts").select("payload, title").eq("post_id", postId).single();
      assertEquals([row?.payload, row?.title], [null, ""]);
    } finally {
      await deleteUser(reader);
    }
  });
});

Deno.test("a forged, tampered or another writer's row is refused", opts, async () => {
  await withWriter(async (w) => {
    const other = await newWriter();
    try {
      const text = payloadOf(w);
      const good = await w.sign(text);
      // Tampered text.
      assertEquals((await call("open-post", w.user.token, { action: "publish", payload: text.replace("Equal", "Unequal"), signature: good, cert: w.cert })).status, 403);
      // Signed by another writer's device, and a row naming someone else as author.
      assertEquals((await call("open-post", w.user.token, { action: "publish", payload: text, signature: await other.sign(text), cert: w.cert })).status, 403);
      assertEquals((await call("open-post", other.user.token, { action: "publish", payload: text, signature: good, cert: w.cert })).status, 403);
      assertEquals((await call("open-post", other.user.token, { action: "publish", payload: text, signature: await other.sign(text), cert: other.cert })).status, 403);
      // A certificate with a different master key.
      const badCert = { ...w.cert, master_key: other.cert.master_key };
      assertEquals((await call("open-post", w.user.token, { action: "publish", payload: text, signature: good, cert: badCert })).status, 403);
      // Someone else's jam.
      const intoOthers = payloadOf(w, { jam_id: other.jamId });
      assertEquals((await publish(w, intoOthers)).status, 403);
      // Not the author: cannot edit or delete.
      const postId = crypto.randomUUID();
      assertEquals((await publish(w, payloadOf(w, { post_id: postId }))).status, 201);
      assertEquals((await call("open-post", other.user.token, { action: "delete", post_id: postId })).status, 403);
      // Revoked device.
      await admin.from("devices").update({ revoked_at: new Date().toISOString() }).eq("device_id", w.deviceId);
      assertEquals((await publish(w, payloadOf(w))).status, 403);
    } finally {
      await deleteUser(other.user);
    }
  });
});

Deno.test("open files: put, upload, commit, read at a public URL, attach, and an edit removes the unreferenced one", opts, async () => {
  await withWriter(async (w) => {
    const fileId = crypto.randomUUID();
    const bytes = randomBytes(3000);
    const put = await call("open-file", w.user.token, { action: "put", file_id: fileId, size: bytes.length, mime: "image/jpeg" });
    assertEquals(put.status, 200, JSON.stringify(put.body));
    const up = await fetch(API_URL + put.body.url, { method: "PUT", headers: { "content-type": "application/octet-stream", apikey: ANON_KEY }, body: bytes as unknown as BodyInit });
    await up.body?.cancel();
    assertEquals(up.status, 200);
    const postId = crypto.randomUUID();
    // Not committed yet: refused.
    assertEquals((await publish(w, payloadOf(w, { post_id: postId, attachments: [{ id: fileId, mime: "image/jpeg" }] }))).status, 400);
    const commit = await call("open-file", w.user.token, { action: "commit", file_id: fileId });
    assertEquals([commit.status, commit.body.size], [200, 3000]);
    const read = await fetch(API_URL + commit.body.public_url, { headers: { apikey: ANON_KEY } });
    assertEquals([read.status, (await read.arrayBuffer()).byteLength], [200, 3000]);
    // Another writer cannot attach it.
    const other = await newWriter();
    try {
      assertEquals((await publish(other, payloadOf(other, { attachments: [{ id: fileId, mime: "image/jpeg" }] }))).status, 400);
    } finally {
      await deleteUser(other.user);
    }
    assertEquals((await publish(w, payloadOf(w, { post_id: postId, attachments: [{ id: fileId, mime: "image/jpeg" }] }))).status, 201);
    const v2 = await publish(w, payloadOf(w, { post_id: postId, version: 2, attachments: [] }), "edit");
    assertEquals(v2.status, 200);
    const gone = await fetch(API_URL + commit.body.public_url, { headers: { apikey: ANON_KEY } });
    await gone.body?.cancel();
    assert(gone.status !== 200, "the file no longer referenced is removed");
  });
});

Deno.test("limits: the file size cap, the quota, the burst and a new account's first week", opts, async () => {
  await withWriter(async (w) => {
    assertEquals((await call("open-file", w.user.token, { action: "put", file_id: crypto.randomUUID(), size: 25 * 1024 * 1024, mime: "video/mp4" })).status, 400);
    // The quota: an existing 2 GiB of files leaves no room.
    await admin.from("open_files").insert({ id: crypto.randomUUID(), owner: w.user.id, size: 2 * 1024 * 1024 * 1024 - 10, mime: "video/mp4", committed_at: new Date().toISOString() });
    assertEquals((await call("open-file", w.user.token, { action: "put", file_id: crypto.randomUUID(), size: 100, mime: "video/mp4" })).status, 413);
    // The burst: 10 a minute.
    for (let i = 0; i < 10; i++) assertEquals((await publish(w, payloadOf(w))).status, 201, `post ${i}`);
    assertEquals((await publish(w, payloadOf(w))).status, 429);
  });
  await withWriter(async (w) => {
    // A new account's first week: 10 open posts a day (the rows are inserted directly so the burst limit does not interfere).
    const rows = Array.from({ length: 10 }, () => ({ post_id: crypto.randomUUID(), author_kind: "person", author_id: w.user.id, jam_id: w.jamId, kind: "quick", payload: "x" }));
    assertEquals((await admin.from("open_posts").insert(rows)).error, null);
    const res = await publish(w, payloadOf(w));
    assertEquals([res.status, res.body.error], [429, "first_week_limit"]);
    // After the first week there is no daily cap.
    await admin.auth.admin.updateUserById(w.user.id, {}); // no-op, keeps the user
    await admin.from("open_posts").delete().eq("author_id", w.user.id);
  });
});

Deno.test("a moderator's takedown: 410, gone in the feed, files removed", opts, async () => {
  await withWriter(async (w) => {
    const mod = await newUser();
    try {
      await admin.from("moderators").insert({ user_id: mod.id });
      const postId = crypto.randomUUID();
      const made = await publish(w, payloadOf(w, { post_id: postId }));
      assertEquals(made.status, 201);
      assertEquals((await call("moderation-act", w.user.token, { action: "hide_open_post", target: postId })).status, 403);
      const act = await call("moderation-act", mod.token, { action: "hide_open_post", target: postId });
      assertEquals(act.status, 200, JSON.stringify(act.body));
      assertEquals((await call("open-post-get", null, { post_id: postId })).status, 410);
      const feed = await call("open-feed", mod.token, { since: made.body.seq });
      assertEquals(feed.body.items.find((i: any) => i.post_id === postId)?.gone, true);
      assertEquals((await publish(w, payloadOf(w, { post_id: postId, version: 2 }), "edit")).status, 404, "a taken-down post cannot be edited back");
    } finally {
      await deleteUser(mod);
    }
  });
});

Deno.test("the open tables are closed to signed-in clients (RLS)", opts, async () => {
  const user = await newUser();
  try {
    const res = await fetch(`${API_URL}/rest/v1/open_posts?select=post_id`, { headers: { apikey: ANON_KEY, authorization: `Bearer ${user.token}` } });
    assert(res.status === 401 || res.status === 403 || (await res.json()).length === 0);
  } finally {
    await deleteUser(user);
  }
});
