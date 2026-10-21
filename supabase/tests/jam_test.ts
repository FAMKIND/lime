// LIME-187: jam posts as long-lived ciphertext fetched without a session, the jams page table, and the fan-out budget of `send`.
// Against the LOCAL stack (Storage enabled): ./supabase/test.sh

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { toBase64 } from "../functions/_shared/bytes.ts";
import { admin, ANON_KEY, API_URL, call, deleteUser, newMasterKey, newUser, randomBytes, registerDevice, type TestUser } from "./helpers.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };

async function withUsers<T>(count: number, fn: (users: TestUser[]) => Promise<T>): Promise<T> {
  const users = await Promise.all(Array.from({ length: count }, newUser));
  try {
    return await fn(users);
  } finally {
    await Promise.all(users.map(deleteUser));
  }
}

async function put(url: string, bytes: Uint8Array): Promise<number> {
  const res = await fetch(API_URL + url, { method: "PUT", headers: { "content-type": "application/octet-stream", apikey: ANON_KEY }, body: bytes as unknown as BodyInit });
  await res.body?.cancel();
  return res.status;
}

async function download(url: string): Promise<{ status: number; bytes: Uint8Array }> {
  const res = await fetch(API_URL + url, { headers: { apikey: ANON_KEY } });
  return { status: res.status, bytes: new Uint8Array(await res.arrayBuffer()) };
}

/** Uploads one jam post (ciphertext) as `user`. */
async function uploadPost(user: TestUser, jamId: string, bytes: Uint8Array): Promise<string> {
  const id = crypto.randomUUID();
  const started = await call("blob", user.token, { action: "put", blob_id: id, size: bytes.length, class: "jam", jam_id: jamId });
  assertEquals(started.status, 200, JSON.stringify(started.body));
  assertEquals(await put(started.body.url, bytes), 200);
  assertEquals((await call("blob", user.token, { action: "commit", blob_id: id })).status, 200);
  return id;
}

Deno.test("a jam post is fetched with no session at all, and the bytes are the ciphertext that was uploaded", opts, async () => {
  await withUsers(1, async ([writer]) => {
    const jamId = crypto.randomUUID();
    const post = randomBytes(40_000);
    const id = await uploadPost(writer, jamId, post);
    // No Authorization header, no apikey: only the id.
    const got = await call("jam-blob-get", null, { blob_id: id });
    assertEquals(got.status, 200, JSON.stringify(got.body));
    const file = await download(got.body.url);
    assertEquals(file.status, 200);
    assertEquals(file.bytes, post);
    // The row records a jam post that never expires.
    const { data } = await admin.from("blobs").select("class, jam_id, expires_at, owner").eq("id", id).single();
    assertEquals([data!.class, data!.jam_id, data!.expires_at, data!.owner], ["jam", jamId, null, writer.id]);
  });
});

Deno.test("a wrong id, a malformed id and an ordinary blob all look the same: 404, and not faster than a real fetch", opts, async () => {
  await withUsers(1, async ([writer]) => {
    const real = await uploadPost(writer, crypto.randomUUID(), randomBytes(1000));
    // An ordinary (non-jam) blob is not reachable this way even with its id.
    const ordinary = crypto.randomUUID();
    const started = await call("blob", writer.token, { action: "put", blob_id: ordinary, size: 100 });
    assertEquals(await put(started.body.url, randomBytes(100)), 200);
    await call("blob", writer.token, { action: "commit", blob_id: ordinary });
    const times: number[] = [];
    for (const bad of [crypto.randomUUID(), "not-an-id", ordinary, ""]) {
      const t0 = performance.now();
      const res = await call("jam-blob-get", null, { blob_id: bad });
      times.push(performance.now() - t0);
      assertEquals(res.status, 404, `${bad}`);
      assertEquals(res.body.error, "not_found");
    }
    const t0 = performance.now();
    assertEquals((await call("jam-blob-get", null, { blob_id: real })).status, 200);
    const found = performance.now() - t0;
    assert(times.every((t) => t >= 100), `a miss waits like a hit (${times.map(Math.round)}ms; a hit took ${Math.round(found)}ms)`);
  });
});

Deno.test("the sweep leaves jam posts alone", opts, async () => {
  await withUsers(1, async ([writer]) => {
    const id = await uploadPost(writer, crypto.randomUUID(), randomBytes(500));
    const { data: target } = await admin.from("sweep_target").select("secret").eq("id", 1).maybeSingle();
    if (!target) return; // a database without the sweep secret cannot be swept at all
    const res = await fetch(`${API_URL}/functions/v1/blob-sweep`, { method: "POST", headers: { "x-sweep-secret": target.secret, "content-type": "application/json" }, body: "{}" });
    await res.body?.cancel();
    assertEquals(res.status, 200);
    assertEquals((await call("jam-blob-get", null, { blob_id: id })).status, 200, "still there after a sweep");
  });
});

Deno.test("jam-page: set, get, only the writer changes it, and ending it deletes every post", opts, async () => {
  await withUsers(2, async ([writer, other]) => {
    const jamId = crypto.randomUUID();
    const set = await call("jam-page", writer.token, { action: "set", jam_id: jamId, title: "Fractions that stick", about: "Short lessons", topics: ["Maths", "Grade 4"], post_count: 2 });
    assertEquals(set.status, 200, JSON.stringify(set.body));
    // A signed-in user reads it; the server holds no post text, only these fields.
    const got = await call("jam-page", other.token, { action: "get", jam_id: jamId });
    assertEquals([got.body.jam.title, got.body.jam.topics, got.body.jam.post_count, got.body.jam.writer_id], ["Fractions that stick", ["Maths", "Grade 4"], 2, writer.id]);
    // Someone else cannot rewrite or end it.
    assertEquals((await call("jam-page", other.token, { action: "set", jam_id: jamId, title: "Mine now", about: "", topics: [], post_count: 0 })).status, 409);
    assertEquals((await call("jam-page", other.token, { action: "end", jam_id: jamId })).status, 409);
    // Bad input is refused.
    assertEquals((await call("jam-page", writer.token, { action: "set", jam_id: jamId, title: "", about: "", topics: [], post_count: 0 })).status, 400);
    assertEquals((await call("jam-page", writer.token, { action: "set", jam_id: jamId, title: "x", about: "", topics: Array(9).fill("t"), post_count: 0 })).status, 400);
    // Two posts, then the jam ends: both are gone for everyone, even with the id.
    const a = await uploadPost(writer, jamId, randomBytes(2000));
    const b = await uploadPost(writer, jamId, randomBytes(2000));
    const fetched = await call("jam-blob-get", null, { blob_id: a });
    assertEquals(fetched.status, 200);
    const ended = await call("jam-page", writer.token, { action: "end", jam_id: jamId });
    assertEquals([ended.status, ended.body.removed], [200, 2]);
    for (const id of [a, b]) assertEquals((await call("jam-blob-get", null, { blob_id: id })).status, 404);
    assertEquals((await download(fetched.body.url)).status !== 200, true, "the stored bytes are gone too");
    assertEquals((await call("jam-page", writer.token, { action: "set", jam_id: jamId, title: "again", about: "", topics: [], post_count: 0 })).status, 409, "an ended jam stays ended");
  });
});

Deno.test("the jam class has its own quota and size cap", opts, async () => {
  await withUsers(1, async ([writer]) => {
    const jamId = crypto.randomUUID();
    const tooBig = await call("blob", writer.token, { action: "put", blob_id: crypto.randomUUID(), size: 26 * 1024 * 1024, class: "jam", jam_id: jamId });
    assertEquals(tooBig.status, 400);
    assertEquals((await call("blob", writer.token, { action: "put", blob_id: crypto.randomUUID(), size: 100, class: "jam" })).status, 400, "a jam post needs its jam id");
    // A writer at the count limit is refused; the ordinary blob quota is untouched by it.
    const rows = Array.from({ length: 20_000 }, () => ({ id: crypto.randomUUID(), owner: writer.id, size: 1, class: "jam", jam_id: jamId, committed_at: new Date().toISOString() }));
    for (let i = 0; i < rows.length; i += 2000) {
      const { error } = await admin.from("blobs").insert(rows.slice(i, i + 2000));
      assertEquals(error, null);
    }
    const over = await call("blob", writer.token, { action: "put", blob_id: crypto.randomUUID(), size: 100, class: "jam", jam_id: jamId });
    assertEquals([over.status, over.body.error], [413, "quota"]);
    const ordinary = await call("blob", writer.token, { action: "put", blob_id: crypto.randomUUID(), size: 100 });
    assertEquals(ordinary.status, 200, "ordinary blobs have their own quota");
  });
});

Deno.test("RLS: signed-in users read the jams table, only the writer changes a row, a signed-out client reads nothing", opts, async () => {
  await withUsers(2, async ([writer, other]) => {
    const jamId = crypto.randomUUID();
    assertEquals((await call("jam-page", writer.token, { action: "set", jam_id: jamId, title: "T", about: "", topics: [], post_count: 0 })).status, 200);
    const as = (token: string | null) =>
      createClient(API_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false }, global: token ? { headers: { Authorization: `Bearer ${token}` } } : {} });
    const mine = await as(writer.token).from("jams").select("jam_id, title").eq("jam_id", jamId);
    assertEquals(mine.data?.length, 1);
    const theirs = await as(other.token).from("jams").select("jam_id, title").eq("jam_id", jamId);
    assertEquals(theirs.data?.length, 1, "any signed-in user can read a page");
    const tamper = await as(other.token).from("jams").update({ title: "Hijacked" }).eq("jam_id", jamId).select();
    assertEquals(tamper.data?.length ?? 0, 0, "not my row: nothing changed");
    const forged = await as(other.token).from("jams").insert({ jam_id: crypto.randomUUID(), writer_id: writer.id, title: "Forged" }).select();
    assertNotEquals(forged.error, null, "a row naming someone else as the writer is refused");
    const anonymous = await as(null).from("jams").select("jam_id").eq("jam_id", jamId);
    assert(anonymous.error !== null || (anonymous.data ?? []).length === 0, "signed out: nothing");
    const { data } = await admin.from("jams").select("title").eq("jam_id", jamId).single();
    assertEquals(data!.title, "T");
  });
});

Deno.test("a fan-out send (50 devices or more) has its own budget; small sends keep the limit they had", opts, async () => {
  await withUsers(15, async ([sender, ...receivers]) => {
    // 14 teachers with ten phones each: 140 devices.
    const devices: string[] = [];
    for (const receiver of receivers) {
      const master = await newMasterKey();
      for (let i = 0; i < 10; i++) devices.push((await registerDevice(receiver, master)).deviceId);
    }
    const ciphertext = toBase64(randomBytes(300));
    const send = (ids: string[]) => call("send", sender.token, { ciphertext, recipients: ids.map((to_device) => ({ to_device, access: { identified: true } })) });
    // 130 devices in one request: more than the 120-per-minute item budget, and accepted (a fan-out).
    const big = await send(devices.slice(0, 130));
    assertEquals(big.status, 200, JSON.stringify(big.body));
    // Small requests are still charged per item at 120 a minute: 45 + 45 + 45 = 135 > 120.
    const other = await newUser();
    try {
      const small = (n: number) => call("send", other.token, { ciphertext: toBase64(randomBytes(300)), recipients: devices.slice(n, n + 45).map((to_device) => ({ to_device, access: { identified: true } })) });
      assertEquals((await small(0)).status, 200);
      assertEquals((await small(45)).status, 200);
      assertEquals((await small(90)).status, 429, "the old limit holds for small sends");
    } finally {
      await deleteUser(other);
    }
  });
});

Deno.test("jam-page by_writer: a signed-in teacher finds the live page, none once it ended, nothing without a session", opts, async () => {
  await withUsers(2, async ([writer, other]) => {
    assertEquals((await call("jam-page", other.token, { action: "by_writer", writer_id: writer.id })).body.jam, null, "no jam yet");
    const jamId = crypto.randomUUID();
    assertEquals((await call("jam-page", writer.token, { action: "set", jam_id: jamId, title: "Fractions", about: "x", topics: ["Maths"], post_count: 1, subscriber_count: 7 })).status, 200);
    const found = await call("jam-page", other.token, { action: "by_writer", writer_id: writer.id });
    assertEquals([found.status, found.body.jam.jam_id, found.body.jam.title, found.body.jam.topics, found.body.jam.subscriber_count], [200, jamId, "Fractions", ["Maths"], 7]);
    assertEquals((await call("jam-page", null, { action: "by_writer", writer_id: writer.id })).status, 401, "a session is needed");
    assertEquals((await call("jam-page", other.token, { action: "by_writer", writer_id: "nope" })).status, 400);
    assertEquals((await call("jam-page", writer.token, { action: "end", jam_id: jamId })).status, 200);
    assertEquals((await call("jam-page", other.token, { action: "by_writer", writer_id: writer.id })).body.jam, null, "ended: none");
  });
});
