// LIME-98c: chunked encrypted attachments, delete-after-fetch, quotas and the sweep. Against the LOCAL stack: ./supabase/test.sh

import { assert, assertEquals } from "jsr:@std/assert@1";
import { admin, ANON_KEY, API_URL, call, deleteUser, newUser, randomBytes, type TestUser } from "./helpers.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };

async function withUsers<T>(count: number, fn: (users: TestUser[]) => Promise<T>): Promise<T> {
  const users = await Promise.all(Array.from({ length: count }, newUser));
  for (const [i, u] of users.entries()) await call("profile-set", u.token, { display_name: `Teacher ${i}` });
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

async function download(url: string): Promise<Uint8Array> {
  const res = await fetch(API_URL + url, { headers: { apikey: ANON_KEY } });
  return new Uint8Array(await res.arrayBuffer());
}

async function sweepSecret(): Promise<string> {
  const { data } = await admin.from("sweep_target").select("secret").eq("id", 1).single();
  return data!.secret;
}

const newId = () => crypto.randomUUID();

Deno.test("an attachment uploads in chunks, commits, downloads in order, and only ciphertext is stored", opts, async () => {
  await withUsers(2, async ([me, other]) => {
    const id = newId();
    const chunks = [randomBytes(70_000), randomBytes(70_000), randomBytes(1234)];
    const size = chunks.reduce((s, c) => s + c.length, 0);
    const started = await call("attachment", me.token, { action: "put", attachment_id: id, size, chunks: 3, recipients: 1 });
    assertEquals(started.status, 200, JSON.stringify(started.body));
    assertEquals(Object.keys(started.body.urls).sort(), ["0", "1", "2"]);
    assertEquals((await call("attachment", me.token, { action: "commit", attachment_id: id })).status, 409, "not complete yet");
    assertEquals((await call("attachment", other.token, { action: "get", attachment_id: id })).status, 404, "not fetchable before commit");
    for (const n of [0, 1, 2]) assertEquals(await put(started.body.urls[String(n)], chunks[n]), 200);
    assertEquals((await call("attachment", me.token, { action: "commit", attachment_id: id })).body.size, size);

    const got = await call("attachment", other.token, { action: "get", attachment_id: id });
    assertEquals(got.status, 200);
    assertEquals(got.body.chunks, 3);
    for (const n of [0, 1, 2]) assertEquals(await download(got.body.urls[n]), chunks[n]);
    assertEquals((await call("attachment", null, { action: "get", attachment_id: id })).status, 401, "never anonymous");
  });
});

Deno.test("an interrupted upload resumes: put again returns only the missing chunks", opts, async () => {
  await withUsers(1, async ([me]) => {
    const id = newId();
    const first = await call("attachment", me.token, { action: "put", attachment_id: id, size: 3000, chunks: 3, recipients: 1 });
    assertEquals(await put(first.body.urls["0"], randomBytes(1000)), 200);
    assertEquals(await put(first.body.urls["1"], randomBytes(1000)), 200);
    // The phone went away before chunk 2. Back again:
    const again = await call("attachment", me.token, { action: "put", attachment_id: id, size: 3000, chunks: 3, recipients: 1 });
    assertEquals(Object.keys(again.body.urls), ["2"], "only the missing chunk");
    assertEquals(await put(again.body.urls["2"], randomBytes(1000)), 200);
    assertEquals((await call("attachment", me.token, { action: "commit", attachment_id: id })).status, 200);
    assertEquals(Object.keys((await call("attachment", me.token, { action: "put", attachment_id: id, size: 3000, chunks: 3, recipients: 1 })).body.urls), [], "complete: nothing to send");
    assertEquals((await call("attachment", me.token, { action: "put", attachment_id: id, size: 9999, chunks: 3, recipients: 1 })).status, 409, "a different shape is refused");
  });
});

Deno.test("only the owner can change an attachment, and it cannot be bigger than declared", opts, async () => {
  await withUsers(2, async ([me, other]) => {
    const id = newId();
    const started = await call("attachment", me.token, { action: "put", attachment_id: id, size: 500, chunks: 1, recipients: 1 });
    assertEquals((await call("attachment", other.token, { action: "put", attachment_id: id, size: 500, chunks: 1, recipients: 1 })).status, 409);
    assertEquals((await call("attachment", other.token, { action: "delete", attachment_id: id })).status, 409);
    await put(started.body.urls["0"], randomBytes(5000));
    assertEquals((await call("attachment", me.token, { action: "commit", attachment_id: id })).status, 413, "more than declared");
    assertEquals((await call("attachment", me.token, { action: "put", attachment_id: id, size: 500, chunks: 1, recipients: 1 })).status, 200, "removed, so it can start again");
    // Validation.
    for (const bad of [{ size: 0, chunks: 1 }, { size: 100, chunks: 0 }, { size: 100, chunks: 61 }, { size: 52 * 1024 * 1024, chunks: 52 }, { size: 100, chunks: 1, recipients: 0 }]) {
      assertEquals((await call("attachment", me.token, { action: "put", attachment_id: newId(), recipients: 1, ...bad })).status, 400, JSON.stringify(bad));
    }
    assertEquals((await call("attachment", me.token, { action: "put", attachment_id: "nope", size: 1, chunks: 1, recipients: 1 })).status, 400);
  });
});

Deno.test("delete after the last recipient has fetched it, and the sweep removes what has expired", opts, async () => {
  await withUsers(3, async ([me, a, b]) => {
    const id = newId();
    const started = await call("attachment", me.token, { action: "put", attachment_id: id, size: 400, chunks: 1, recipients: 2 });
    await put(started.body.urls["0"], randomBytes(400));
    await call("attachment", me.token, { action: "commit", attachment_id: id });
    const expiryOf = async () => new Date((await admin.from("attachments").select("expires_at").eq("id", id).single()).data!.expires_at).getTime();
    const thirtyDays = Date.now() + 29 * 86_400_000;
    assert(await expiryOf() > thirtyDays, "30 days by default");
    await call("attachment", a.token, { action: "get", attachment_id: id });
    await call("attachment", a.token, { action: "get", attachment_id: id });
    assert(await expiryOf() > thirtyDays, "one of two recipients (twice) is not everyone");
    await call("attachment", b.token, { action: "get", attachment_id: id });
    assert(await expiryOf() < Date.now() + 3_700_000, "everyone has it: due for deletion within the hour");

    // The sweep refuses a caller without its secret, and removes only what has expired.
    const secret = await sweepSecret();
    const sweep = (s: string) => fetch(`${API_URL}/functions/v1/blob-sweep`, { method: "POST", headers: { "x-sweep-secret": s, apikey: ANON_KEY } });
    assertEquals((await sweep("wrong")).status, 401);
    const first = await (await sweep(secret)).json();
    assertEquals((await admin.from("attachments").select("id").eq("id", id)).data!.length, 1, "not expired yet: kept");
    assert(first.attachments >= 0);
    await admin.from("attachments").update({ expires_at: new Date(Date.now() - 1000).toISOString() }).eq("id", id);
    const swept = await (await sweep(secret)).json();
    assert(swept.attachments >= 1);
    assertEquals((await admin.from("attachments").select("id").eq("id", id)).data!.length, 0, "the row is gone");
    const left = await admin.storage.from("blobs").list(`a/${id}`);
    assertEquals(left.data?.length ?? 0, 0, "and its Storage object");
    assertEquals((await call("attachment", a.token, { action: "get", attachment_id: id })).status, 404);
  });
});

Deno.test("a forward shares the same file with more people: it stays until they have fetched it", opts, async () => {
  await withUsers(4, async ([me, a, b, c]) => {
    const id = newId();
    const started = await call("attachment", me.token, { action: "put", attachment_id: id, size: 400, chunks: 1, recipients: 1 });
    await put(started.body.urls["0"], randomBytes(400));
    await call("attachment", me.token, { action: "commit", attachment_id: id });
    const row = async () => (await admin.from("attachments").select("recipients, expires_at").eq("id", id).single()).data!;
    await call("attachment", a.token, { action: "get", attachment_id: id });
    assert(new Date((await row()).expires_at).getTime() < Date.now() + 3_700_000, "everyone (one) has it: due within the hour");
    // A holder forwards it to two more people: it lives on, and now waits for them too.
    const shared = await call("attachment", a.token, { action: "share", attachment_id: id, recipients: 2 });
    assertEquals(shared.status, 200);
    const after = await row();
    assertEquals(after.recipients, 3);
    assert(new Date(after.expires_at).getTime() > Date.now() + 6 * 86_400_000, "kept for about a week more");
    assert(new Date(after.expires_at).getTime() <= Date.now() + 30 * 86_400_000, "never past 30 days");
    await call("attachment", b.token, { action: "get", attachment_id: id });
    assert(new Date((await row()).expires_at).getTime() > Date.now() + 6 * 86_400_000, "two of three: kept");
    await call("attachment", c.token, { action: "get", attachment_id: id });
    assert(new Date((await row()).expires_at).getTime() < Date.now() + 3_700_000, "all of them have it: due for deletion");
    // Not for an unknown file or bad numbers; and only the owner can delete it.
    assertEquals((await call("attachment", a.token, { action: "share", attachment_id: newId(), recipients: 1 })).status, 404);
    assertEquals((await call("attachment", a.token, { action: "share", attachment_id: id, recipients: 0 })).status, 400);
    assertEquals((await call("attachment", a.token, { action: "delete", attachment_id: id })).status, 409);
  });
});

Deno.test("an upload never completed is swept after a day, and expired blobs too", opts, async () => {
  await withUsers(1, async ([me]) => {
    const id = newId();
    await call("attachment", me.token, { action: "put", attachment_id: id, size: 100, chunks: 1, recipients: 1 });
    await admin.from("attachments").update({ created_at: new Date(Date.now() - 2 * 86_400_000).toISOString() }).eq("id", id);
    const blob = newId();
    const bs = await call("blob", me.token, { action: "put", blob_id: blob, size: 100, expires_in_days: 1 });
    await put(bs.body.url, randomBytes(100));
    await call("blob", me.token, { action: "commit", blob_id: blob });
    await admin.from("blobs").update({ expires_at: new Date(Date.now() - 1000).toISOString() }).eq("id", blob);
    const res = await fetch(`${API_URL}/functions/v1/blob-sweep`, { method: "POST", headers: { "x-sweep-secret": await sweepSecret(), apikey: ANON_KEY } });
    const out = await res.json();
    assert(out.attachments >= 1 && out.blobs >= 1, JSON.stringify(out));
    assertEquals((await admin.from("attachments").select("id").eq("id", id)).data!.length, 0);
    assertEquals((await admin.from("blobs").select("id").eq("id", blob)).data!.length, 0);
  });
});

Deno.test("attachment quotas count what a user still has on the server", opts, async () => {
  await withUsers(1, async ([me]) => {
    let refused = 0;
    for (let i = 0; i < 7; i++) {
      const res = await call("attachment", me.token, { action: "put", attachment_id: newId(), size: 50 * 1024 * 1024, chunks: 50, recipients: 1 });
      if (res.status === 413) refused++;
    }
    assertEquals(refused, 1, "the seventh 50 MB file goes over 300 MB");
  });
});
