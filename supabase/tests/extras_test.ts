// LIME-214, LIME-217, LIME-226a: a profile's links, background image and background video through `avatar` slots, and `profile-get`'s `since`.
// Local: ./supabase/test.sh. Staging: ./supabase/smoke-extras-staging.sh (throwaway users, deleted at the end).

import { assert, assertEquals } from "jsr:@std/assert@1";
import { admin, ANON_KEY, API_URL, call, deleteUser, newUser, randomBytes, SERVICE_ROLE_KEY, type TestUser } from "./helpers.ts";

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

async function put(url: string, bytes: Uint8Array, type: string): Promise<number> {
  const res = await fetch(API_URL + url, { method: "PUT", headers: { "content-type": type, apikey: ANON_KEY }, body: bytes as unknown as BodyInit });
  await res.body?.cancel();
  return res.status;
}

async function download(url: string): Promise<Uint8Array> {
  const res = await fetch(API_URL + url, { headers: { apikey: ANON_KEY } });
  return new Uint8Array(await res.arrayBuffer());
}

/** put, upload and commit one slot's bytes; returns the commit response. */
async function publish(user: TestUser, slot: string, bytes: Uint8Array, type: string) {
  const first = await call("avatar", user.token, { action: "put", slot, size: bytes.length });
  assertEquals(first.status, 200, JSON.stringify(first.body));
  assertEquals(await put(first.body.url, bytes, type), 200, `the ${slot} upload`);
  return await call("avatar", user.token, { action: "commit", slot });
}

Deno.test("the bucket allows the three kinds of public object, up to 6 MiB", opts, async () => {
  const res = await fetch(`${API_URL}/storage/v1/bucket/public-avatars`, { headers: { apikey: ANON_KEY, authorization: `Bearer ${SERVICE_ROLE_KEY}` } });
  const bucket = await res.json();
  assertEquals(bucket.file_size_limit, 6291456);
  assertEquals([...bucket.allowed_mime_types].sort(), ["application/json", "image/jpeg", "video/mp4"]);
  assertEquals(bucket.public, false);
});

Deno.test("links, a background and a background video are each published, read by someone else, hidden and removed", opts, async () => {
  await withUsers(2, async ([alice, bob]) => {
    const links = new TextEncoder().encode(JSON.stringify([{ title: "My class", url: "https://example.com/class" }]));
    const still = randomBytes(3000); still[0] = 0xff; still[1] = 0xd8;
    const clip = randomBytes(50_000);
    for (const [slot, bytes, type] of [["links", links, "application/json"], ["background", still, "image/jpeg"], ["background_video", clip, "video/mp4"]] as const) {
      const committed = await publish(alice, slot, bytes, type);
      assertEquals(committed.status, 200, `${slot} commit: ${JSON.stringify(committed.body)}`);
      const got = await call("avatar", bob.token, { action: "get", user_id: alice.id, slot });
      assertEquals(got.status, 200, `${slot} get`);
      assertEquals(got.body.version, committed.body.version);
      assertEquals(await download(got.body.url), bytes, `${slot} comes back byte for byte`);
    }
    // The photo is separate: Alice has none.
    assertEquals((await call("avatar", bob.token, { action: "get", user_id: alice.id })).status, 404, "the photo slot is its own");
    // Contacts only deletes the public copy of that slot only.
    assertEquals((await call("avatar", alice.token, { action: "visibility", slot: "links", visibility: "contacts" })).status, 200);
    assertEquals((await call("avatar", bob.token, { action: "get", user_id: alice.id, slot: "links" })).status, 404);
    assertEquals((await call("avatar", bob.token, { action: "get", user_id: alice.id, slot: "background" })).status, 200, "the others stay");
    // Remove the video: the still stays.
    assertEquals((await call("avatar", alice.token, { action: "remove", slot: "background_video" })).status, 200);
    assertEquals((await call("avatar", bob.token, { action: "get", user_id: alice.id, slot: "background_video" })).status, 404);
    assertEquals((await call("avatar", bob.token, { action: "get", user_id: alice.id, slot: "background" })).status, 200);
    await call("avatar", alice.token, { action: "remove", slot: "background" });
  });
});

Deno.test("each slot has its own size limit, declared and actual, and an unknown slot is refused", opts, async () => {
  await withUsers(1, async ([alice]) => {
    assertEquals((await call("avatar", alice.token, { action: "put", slot: "links", size: 8 * 1024 + 1 })).status, 400, "links over 8 KB");
    assertEquals((await call("avatar", alice.token, { action: "put", slot: "background", size: 1024 * 1024 + 1 })).status, 400, "a background over 1 MiB");
    assertEquals((await call("avatar", alice.token, { action: "put", slot: "background_video", size: 6 * 1024 * 1024 + 1 })).status, 400, "a clip over 6 MiB");
    assertEquals((await call("avatar", alice.token, { action: "put", slot: "background_video", size: 6 * 1024 * 1024 })).status, 200, "exactly 6 MiB is fine");
    assertEquals((await call("avatar", alice.token, { action: "put", slot: "nope", size: 10 })).status, 400, "an unknown slot");
    // Declared small, uploaded big (the bucket allows 6 MiB): the commit refuses it and removes it.
    const first = await call("avatar", alice.token, { action: "put", slot: "links", size: 100 });
    assertEquals(await put(first.body.url, randomBytes(9 * 1024), "application/json"), 200, "the bucket itself would take it");
    const commit = await call("avatar", alice.token, { action: "commit", slot: "links" });
    assertEquals(commit.status, 413, JSON.stringify(commit.body));
    assertEquals((await call("avatar", alice.token, { action: "commit", slot: "links" })).status, 409, "and it is gone");
  });
});

Deno.test("profile-get gives a findable person's account date and nothing for someone who hid", opts, async () => {
  await withUsers(2, async ([alice, bob]) => {
    const seen = await call("profile-get", bob.token, { user_id: alice.id });
    assertEquals(seen.status, 200);
    assert(typeof seen.body.profile.since === "number" && seen.body.profile.since > 1_700_000_000_000, "since is a time in milliseconds");
    assertEquals((await call("profile-set", alice.token, { display_name: "Teacher 0", hide_from_search: true })).status, 200);
    assertEquals((await call("profile-get", bob.token, { user_id: alice.id })).body.profile.since, null, "hidden: no date");
    const own = await call("profile-get", alice.token, {});
    assert(typeof own.body.profile.since === "number", "your own profile has it");
  });
});
