// LIME-98b: the blob store and public avatars. Against the LOCAL stack (Storage enabled): ./supabase/test.sh

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
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

const jpeg = (n: number) => { const b = randomBytes(n); b[0] = 0xff; b[1] = 0xd8; return b; };

async function put(url: string, bytes: Uint8Array, type: string): Promise<number> {
  const res = await fetch(API_URL + url, { method: "PUT", headers: { "content-type": type, apikey: ANON_KEY }, body: bytes as unknown as BodyInit });
  await res.body?.cancel();
  return res.status;
}

async function download(url: string): Promise<{ status: number; bytes: Uint8Array }> {
  const res = await fetch(API_URL + url, { headers: { apikey: ANON_KEY } });
  return { status: res.status, bytes: new Uint8Array(await res.arrayBuffer()) };
}

Deno.test("a signed-in user can read a public avatar, a signed-out one cannot, and the buckets are private", opts, async () => {
  await withUsers(2, async ([me, other]) => {
    const photo = jpeg(30_000);
    const started = await call("avatar", me.token, { action: "put", size: photo.length });
    assertEquals(started.status, 200, JSON.stringify(started.body));
    assertEquals(await put(started.body.url, photo, "image/jpeg"), 200);
    assertEquals((await call("avatar", me.token, { action: "commit" })).status, 200);

    // Another signed-in user gets a signed URL and the bytes.
    const got = await call("avatar", other.token, { action: "get", user_id: me.id });
    assertEquals(got.status, 200, JSON.stringify(got.body));
    const file = await download(got.body.url);
    assertEquals(file.status, 200);
    assertEquals(file.bytes, photo);

    // No token at all: nothing. The bucket itself is not public, and the direct paths are closed.
    assertEquals((await call("avatar", null, { action: "get", user_id: me.id })).status, 401);
    for (const direct of [
      `/storage/v1/object/public/public-avatars/${me.id}.jpg`,
      `/storage/v1/object/public-avatars/${me.id}.jpg`,
      `/storage/v1/object/authenticated/public-avatars/${me.id}.jpg`,
    ]) {
      const res = await fetch(API_URL + direct, { headers: { apikey: ANON_KEY } });
      await res.body?.cancel();
      assert(res.status >= 400, `${direct} must not be readable (${res.status})`);
      const asUser = await fetch(API_URL + direct, { headers: { apikey: ANON_KEY, authorization: `Bearer ${other.token}` } });
      await asUser.body?.cancel();
      assert(asUser.status >= 400, `${direct} must not be readable by a signed-in user directly (${asUser.status})`);
    }
    const listed = await fetch(`${API_URL}/storage/v1/object/list/public-avatars`, {
      method: "POST", headers: { apikey: ANON_KEY, authorization: `Bearer ${other.token}`, "content-type": "application/json" }, body: JSON.stringify({ prefix: "" }),
    });
    const names = listed.ok ? (await listed.json() as unknown[]) : [];
    assertEquals(names.length, 0, "a signed-in user cannot list the bucket");

    // Own profile shows the version; others' profile-get too is not needed, the avatar call is the way.
    const own = await call("profile-get", me.token, {});
    assertEquals(own.body.profile.photo_visibility, "everyone");
    assert(own.body.profile.avatar_version > 0);
  });
});

Deno.test("public avatars: 1 MB, JPEG only, the owner only; contacts-only deletes the public copy", opts, async () => {
  await withUsers(2, async ([me, other]) => {
    assertEquals((await call("avatar", me.token, { action: "put", size: 1024 * 1024 + 1 })).status, 400, "too big is refused up front");
    assertEquals((await call("avatar", me.token, { action: "put", size: 0 })).status, 400);
    const started = await call("avatar", me.token, { action: "put", size: 5000 });
    assertEquals(await put(started.body.url, randomBytes(5000), "image/png"), 400, "only JPEG is accepted by the bucket");
    assert((await put(started.body.url, jpeg(2 * 1024 * 1024), "image/jpeg")) >= 400, "the bucket refuses more than 1 MB");
    assertEquals((await call("avatar", me.token, { action: "commit" })).status, 409, "nothing was uploaded");

    const photo = jpeg(8000);
    const again = await call("avatar", me.token, { action: "put", size: photo.length });
    assertEquals(await put(again.body.url, photo, "image/jpeg"), 200);
    await call("avatar", me.token, { action: "commit" });
    // Someone else's upload URL cannot overwrite mine: each URL is for its owner's path.
    const theirs = await call("avatar", other.token, { action: "put", size: 100 });
    assertNotEquals(theirs.body.url, again.body.url);

    // Contacts only: the public copy is deleted from the server, and strangers get nothing.
    assertEquals((await call("avatar", me.token, { action: "visibility", visibility: "contacts" })).status, 200);
    assertEquals((await call("avatar", other.token, { action: "get", user_id: me.id })).status, 404);
    const { data } = await admin.storage.from("public-avatars").list("", { search: me.id });
    assertEquals((data ?? []).filter((o) => o.name.startsWith(me.id)).length, 0, "the public object is gone");
    assertEquals((await call("profile-get", me.token, {})).body.profile.avatar_version, null);

    // Back to everyone with a new upload, then remove.
    assertEquals((await call("avatar", me.token, { action: "visibility", visibility: "bogus" })).status, 400);
    const third = await call("avatar", me.token, { action: "put", size: photo.length });
    await put(third.body.url, photo, "image/jpeg");
    assertEquals((await call("avatar", me.token, { action: "commit" })).status, 200);
    assertEquals((await call("avatar", other.token, { action: "get", user_id: me.id })).status, 200);
    assertEquals((await call("avatar", me.token, { action: "remove" })).status, 200);
    assertEquals((await call("avatar", other.token, { action: "get", user_id: me.id })).status, 404);
  });
});

Deno.test("blobs: ciphertext bytes round trip, only the owner can replace or delete, and ids are capabilities", opts, async () => {
  await withUsers(2, async ([me, other]) => {
    const id = crypto.randomUUID();
    const bytes = randomBytes(40_000);
    const started = await call("blob", me.token, { action: "put", blob_id: id, size: bytes.length });
    assertEquals(started.status, 200, JSON.stringify(started.body));
    assertEquals((await call("blob", other.token, { action: "get", blob_id: id })).status, 404, "not downloadable before it is committed");
    assertEquals(await put(started.body.url, bytes, "application/octet-stream"), 200);
    assertEquals((await call("blob", me.token, { action: "commit", blob_id: id })).status, 200);

    const got = await call("blob", other.token, { action: "get", blob_id: id });
    assertEquals(got.status, 200);
    assertEquals((await download(got.body.url)).bytes, bytes);
    assertEquals((await call("blob", null, { action: "get", blob_id: id })).status, 401, "never anonymous");
    assertEquals((await call("blob", other.token, { action: "get", blob_id: crypto.randomUUID() })).status, 404);

    assertEquals((await call("blob", other.token, { action: "put", blob_id: id, size: 10 })).status, 409, "not theirs to replace");
    assertEquals((await call("blob", other.token, { action: "delete", blob_id: id })).status, 409, "not theirs to delete");
    assertEquals((await call("blob", me.token, { action: "delete", blob_id: id })).status, 200);
    assertEquals((await call("blob", other.token, { action: "get", blob_id: id })).status, 404);
  });
});

Deno.test("blobs: quotas (a lower limit per file, a count, and bytes) and the declared size", opts, async () => {
  await withUsers(1, async ([me]) => {
    assertEquals((await call("blob", me.token, { action: "put", blob_id: crypto.randomUUID(), size: 26 * 1024 * 1024 })).status, 400, "over the per-file limit");
    assertEquals((await call("blob", me.token, { action: "put", blob_id: "not-a-uuid", size: 10 })).status, 400);

    // More bytes than declared: refused at commit, and removed.
    const id = crypto.randomUUID();
    const started = await call("blob", me.token, { action: "put", blob_id: id, size: 1000 });
    await put(started.body.url, randomBytes(3000), "application/octet-stream");
    assertEquals((await call("blob", me.token, { action: "commit", blob_id: id })).status, 413);
    assertEquals((await call("blob", me.token, { action: "get", blob_id: id })).status, 404);

    // The total quota (200 MB by default) counts declared sizes: fill it with declarations (no uploads needed).
    let refused = 0;
    for (let i = 0; i < 9; i++) {
      const res = await call("blob", me.token, { action: "put", blob_id: crypto.randomUUID(), size: 25 * 1024 * 1024 });
      if (res.status === 413) refused++;
    }
    assertEquals(refused, 1, "the ninth 25 MB blob goes over 200 MB");
  });
});

Deno.test("the blobs bucket is private: no direct read or listing, even for a signed-in user", opts, async () => {
  await withUsers(2, async ([me, other]) => {
    const id = crypto.randomUUID();
    const started = await call("blob", me.token, { action: "put", blob_id: id, size: 100 });
    await put(started.body.url, randomBytes(100), "application/octet-stream");
    await call("blob", me.token, { action: "commit", blob_id: id });
    for (const headers of [{ apikey: ANON_KEY } as Record<string, string>, { apikey: ANON_KEY, authorization: `Bearer ${other.token}` }]) {
      for (const path of [`/storage/v1/object/blobs/${id}`, `/storage/v1/object/authenticated/blobs/${id}`, `/storage/v1/object/public/blobs/${id}`]) {
        const res = await fetch(API_URL + path, { headers });
        await res.body?.cancel();
        assert(res.status >= 400, `${path} must be closed (${res.status})`);
      }
    }
  });
});
