// LIME-275: handing a band's publishing to another owner (jam-page handover_*). Against the LOCAL stack: ./supabase/test.sh
import { assertEquals } from "jsr:@std/assert@1";
import { admin, ANON_KEY, API_URL, call, deleteUser, newUser, randomBytes, type TestUser } from "./helpers.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };

async function withUsers<T>(count: number, fn: (users: TestUser[]) => Promise<T>): Promise<T> {
  const users = await Promise.all(Array.from({ length: count }, newUser));
  try {
    return await fn(users);
  } finally {
    await Promise.all(users.map(deleteUser));
  }
}

const page = (user: TestUser, jamId: string, title: string) =>
  call("jam-page", user.token, { action: "set", jam_id: jamId, title, about: "", topics: [], post_count: 0 });

async function uploadPost(user: TestUser, jamId: string): Promise<string> {
  const id = crypto.randomUUID();
  const bytes = randomBytes(2000);
  const started = await call("blob", user.token, { action: "put", blob_id: id, size: bytes.length, class: "jam", jam_id: jamId });
  assertEquals(started.status, 200, JSON.stringify(started.body));
  const res = await fetch(API_URL + started.body.url, { method: "PUT", headers: { "content-type": "application/octet-stream", apikey: ANON_KEY }, body: bytes as unknown as BodyInit });
  await res.body?.cancel();
  assertEquals((await call("blob", user.token, { action: "commit", blob_id: id })).status, 200);
  return id;
}

Deno.test("handover: offer, accept, the writer changes, by_writer follows and the old writer can no longer change the band", opts, async () => {
  await withUsers(3, async ([alice, bob, carol]) => {
    const own = crypto.randomUUID(), band = crypto.randomUUID();
    assertEquals((await page(alice, own, "Alice")).status, 200);
    assertEquals((await page(alice, band, "lime juice")).status, 200);
    assertEquals((await page(bob, crypto.randomUUID(), "Bob")).status, 200);   // Bob has his own space too, so the band is not his oldest jam
    const post = await uploadPost(alice, band);

    // Only the writer offers; nobody else's band; not to yourself; not to nobody.
    assertEquals((await call("jam-page", bob.token, { action: "handover_offer", jam_id: band, new_writer_id: carol.id })).status, 409, "not the writer");
    assertEquals((await call("jam-page", alice.token, { action: "handover_offer", jam_id: band, new_writer_id: alice.id })).status, 400, "not to myself");
    assertEquals((await call("jam-page", alice.token, { action: "handover_offer", jam_id: band, new_writer_id: crypto.randomUUID() })).status, 404, "no such teacher");
    assertEquals((await call("jam-page", alice.token, { action: "handover_offer", jam_id: band, new_writer_id: carol.id })).status, 409, "Carol has no space of her own yet: the band would become her profile");
    // 1e550: my own profile space (the oldest jam) can never be handed over.
    const own409 = await call("jam-page", alice.token, { action: "handover_offer", jam_id: own, new_writer_id: bob.id });
    assertEquals([own409.status, own409.body.error], [409, "own_space"], JSON.stringify(own409.body));

    // The offer changes nothing until it is accepted.
    assertEquals((await call("jam-page", alice.token, { action: "handover_offer", jam_id: band, new_writer_id: bob.id })).status, 200);
    assertEquals((await call("jam-page", alice.token, { action: "get", jam_id: band })).body.jam.writer_id, alice.id);
    const offers = await call("jam-page", bob.token, { action: "handover_offers" });
    assertEquals(offers.body.offers.map((o: { jam_id: string; from_writer: string; title: string }) => [o.jam_id, o.from_writer, o.title]), [[band, alice.id, "lime juice"]]);
    assertEquals((await call("jam-page", carol.token, { action: "handover_offers" })).body.offers, [], "only the named teacher sees it");
    assertEquals((await call("jam-page", carol.token, { action: "handover_accept", jam_id: band })).status, 404, "only the named teacher can accept");
    assertEquals((await call("jam-page", alice.token, { action: "handover_accept", jam_id: band })).status, 404, "not the offerer either");

    // Accept.
    assertEquals((await call("jam-page", bob.token, { action: "handover_accept", jam_id: band })).status, 200);
    assertEquals((await call("jam-page", carol.token, { action: "get", jam_id: band })).body.jam.writer_id, bob.id, "the writer is now Bob");
    assertEquals((await call("jam-page", carol.token, { action: "by_writer", writer_id: bob.id })).body.others.map((j: { jam_id: string }) => j.jam_id), [band], "Bob's bands follow");
    assertEquals((await call("jam-page", carol.token, { action: "by_writer", writer_id: alice.id })).body.others, [], "and Alice no longer lists it");
    assertEquals((await call("jam-page", bob.token, { action: "handover_offers" })).body.offers, [], "the offer is spent");
    assertEquals((await admin.from("blobs").select("owner").eq("id", post).single()).data!.owner, bob.id, "the post ciphertext is Bob's now");
    // Alice can no longer change it; Bob can.
    assertEquals((await page(alice, band, "mine again")).status, 409);
    assertEquals((await call("jam-page", alice.token, { action: "end", jam_id: band })).status, 409);
    assertEquals((await page(bob, band, "lime juice")).status, 200);
    // And it can be handed back the same way.
    assertEquals((await call("jam-page", bob.token, { action: "handover_offer", jam_id: band, new_writer_id: alice.id })).status, 200);
    assertEquals((await call("jam-page", alice.token, { action: "handover_accept", jam_id: band })).status, 200);
    assertEquals((await call("jam-page", carol.token, { action: "get", jam_id: band })).body.jam.writer_id, alice.id);
  });
});

Deno.test("handover: the writer can cancel, the named teacher can decline, a new offer replaces the old one, an ended band cannot be offered", opts, async () => {
  await withUsers(3, async ([alice, bob, carol]) => {
    const own = crypto.randomUUID(), band = crypto.randomUUID();
    await page(alice, own, "Alice");
    await page(alice, band, "Band");
    await page(bob, crypto.randomUUID(), "Bob");
    await page(carol, crypto.randomUUID(), "Carol");
    assertEquals((await call("jam-page", alice.token, { action: "handover_offer", jam_id: band, new_writer_id: bob.id })).status, 200);
    assertEquals((await call("jam-page", alice.token, { action: "handover_cancel", jam_id: band })).status, 200);
    assertEquals((await call("jam-page", bob.token, { action: "handover_offers" })).body.offers, []);
    assertEquals((await call("jam-page", alice.token, { action: "handover_offer", jam_id: band, new_writer_id: bob.id })).status, 200);
    assertEquals((await call("jam-page", alice.token, { action: "handover_offer", jam_id: band, new_writer_id: carol.id })).status, 200);
    assertEquals((await call("jam-page", bob.token, { action: "handover_offers" })).body.offers, [], "replaced: Bob's offer is gone");
    assertEquals((await call("jam-page", bob.token, { action: "handover_accept", jam_id: band })).status, 404);
    assertEquals((await call("jam-page", carol.token, { action: "handover_decline", jam_id: band })).status, 200);
    assertEquals((await call("jam-page", carol.token, { action: "handover_accept", jam_id: band })).status, 404, "declined");
    assertEquals((await call("jam-page", carol.token, { action: "get", jam_id: band })).body.jam.writer_id, alice.id, "still Alice's");
    // An ended band cannot be offered.
    assertEquals((await call("jam-page", alice.token, { action: "end", jam_id: band })).status, 200);
    assertEquals((await call("jam-page", alice.token, { action: "handover_offer", jam_id: band, new_writer_id: bob.id })).status, 404);
  });
});

Deno.test("handover: a band that ends or is taken down before it is accepted cannot be taken", opts, async () => {
  await withUsers(2, async ([alice, bob]) => {
    const own = crypto.randomUUID(), band = crypto.randomUUID();
    await page(alice, own, "Alice");
    await page(alice, band, "Band");
    await page(bob, crypto.randomUUID(), "Bob");
    assertEquals((await call("jam-page", alice.token, { action: "handover_offer", jam_id: band, new_writer_id: bob.id })).status, 200);
    assertEquals((await call("jam-page", alice.token, { action: "end", jam_id: band })).status, 200);
    assertEquals((await call("jam-page", bob.token, { action: "handover_accept", jam_id: band })).status, 404, "ended meanwhile");
  });
});
