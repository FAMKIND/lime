// LIME-113: deleting an account. Against the LOCAL stack: ./supabase/test.sh
import { assert, assertEquals } from "jsr:@std/assert@1";
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { toBase64 } from "../functions/_shared/bytes.ts";
import { admin, ANON_KEY, API_URL, call, deleteUser, emailedCode, newMasterKey, newUser, randomBytes, registerDevice, sessionIdOf, type TestUser } from "./helpers.ts";

const opts = { sanitizeOps: false, sanitizeResources: false };

/** A user whose password we know, with a session that already passed both sign-in steps. */
async function userWithPassword(): Promise<TestUser & { password: string }> {
  const email = `d-${crypto.randomUUID()}@example.invalid`;
  const password = "correct-horse-" + crypto.randomUUID().slice(0, 8);
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
  if (error || !data.user) throw new Error("could not create the user");
  const anon = createClient(API_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const signedIn = await anon.auth.signInWithPassword({ email, password });
  const token = signedIn.data.session!.access_token;
  await admin.from("auth_proofs").upsert({ session_id: sessionIdOf(token), user_id: data.user.id, password_ok: true, code_ok: true, verified_at: new Date().toISOString() });
  return { id: data.user.id, token, email, password };
}

async function put(url: string, bytes: Uint8Array) {
  const res = await fetch(API_URL + url, { method: "PUT", headers: { "content-type": "application/octet-stream", apikey: ANON_KEY }, body: bytes as unknown as BodyInit });
  await res.body?.cancel();
}

async function blobFor(user: TestUser, jamId?: string): Promise<string> {
  const id = crypto.randomUUID();
  const bytes = randomBytes(1500);
  const body: Record<string, unknown> = { action: "put", blob_id: id, size: bytes.length };
  if (jamId) Object.assign(body, { class: "jam", jam_id: jamId });
  const started = await call("blob", user.token, body);
  assertEquals(started.status, 200, JSON.stringify(started.body));
  await put(started.body.url, bytes);
  assertEquals((await call("blob", user.token, { action: "commit", blob_id: id })).status, 200);
  return id;
}

async function rows(table: string, column: string, value: string): Promise<number> {
  const { count } = await admin.from(table).select("*", { count: "exact", head: true }).eq(column, value);
  return count ?? 0;
}

Deno.test("deleting an account removes everything of it, nothing of anyone else's, holds the username and logs a hash", opts, async () => {
  const a = await userWithPassword();
  const b = await newUser();
  try {
    const username = "gone" + crypto.randomUUID().slice(0, 6);
    assertEquals((await call("profile-set", a.token, { display_name: "Ann", username })).status, 200);
    assertEquals((await call("profile-set", b.token, { display_name: "Bea" })).status, 200);
    await registerDevice(a, await newMasterKey());
    await registerDevice(b, await newMasterKey());
    const jamId = crypto.randomUUID();
    assertEquals((await call("jam-page", a.token, { action: "set", jam_id: jamId, title: "Ann's jam", about: "", topics: [], post_count: 1, subscriber_count: 0 })).status, 200);
    const aBlob = await blobFor(a);
    const aPost = await blobFor(a, jamId);
    const bBlob = await blobFor(b);
    await admin.from("moderation_reports").insert({ reporter: a.id, kind: "person", reason: "other", sealed: "\\x" + "00".repeat(60) });

    // Both steps are needed: a wrong password, a wrong code, and no code at all are refused.
    assertEquals((await call("account-delete-start", a.token, { password: "nope" })).status, 401);
    const started = await call("account-delete-start", a.token, { password: a.password });
    assertEquals(started.status, 200, JSON.stringify(started.body));
    const code = await emailedCode(a.email);
    assertEquals((await call("account-delete", a.token, { password: "nope", code })).status, 401);
    assertEquals((await call("account-delete", a.token, { password: a.password, code: "000000" })).status, 400);
    assertEquals(await rows("profiles", "user_id", a.id), 1, "nothing was deleted by the refusals");

    const done = await call("account-delete", a.token, { password: a.password, code });
    assertEquals(done.status, 200, JSON.stringify(done.body));

    for (const [table, column] of [["profiles", "user_id"], ["devices", "user_id"], ["master_keys", "user_id"], ["blobs", "owner"], ["jams", "writer_id"], ["moderation_reports", "reporter"], ["auth_proofs", "user_id"]]) {
      assertEquals(await rows(table, column, a.id), 0, `${table} of the deleted account is gone`);
    }
    assertEquals(await rows("blobs", "id", aBlob) + await rows("blobs", "id", aPost), 0);
    assertEquals((await call("jam-blob-get", null, { blob_id: aPost })).status, 404, "its jam post cannot be fetched");
    // Anyone else's data is untouched.
    assertEquals(await rows("profiles", "user_id", b.id), 1);
    assertEquals(await rows("devices", "user_id", b.id), 1);
    assertEquals(await rows("blobs", "id", bBlob), 1);
    // The account cannot sign in or call anything.
    assertEquals((await call("profile-get", a.token, {})).status, 401);
    const anon = createClient(API_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    assert((await anon.auth.signInWithPassword({ email: a.email, password: a.password })).error, "cannot sign in");
    // The log: a hash and a time, nothing else. The username is held.
    const { data: log } = await admin.from("deleted_accounts").select("*").eq("id_hash", await hash(a.id));
    assertEquals(log!.length, 1);
    assertEquals(Object.keys(log![0]).sort(), ["deleted_at", "id_hash"]);
    assert(!JSON.stringify(log).includes(a.id));
    const taken = await call("profile-set", b.token, { display_name: "Bea", username });
    assertEquals([taken.status, taken.body.error], [409, "username_taken"], "nobody can take it for 30 days");
    // After the hold, it is free again.
    await admin.from("held_usernames").update({ held_until: new Date(Date.now() - 1000).toISOString() }).eq("username", username.toLowerCase());
    assertEquals((await call("profile-set", b.token, { display_name: "Bea", username })).status, 200);
    await admin.rpc("sweep_held_usernames");
    assertEquals(await rows("held_usernames", "username", username.toLowerCase()), 0);
    // The email can sign up again at once.
    const again = await admin.auth.admin.createUser({ email: a.email, password: "another-password-1", email_confirm: true });
    assert(!again.error, "the email is free");
    if (again.data.user) await admin.auth.admin.deleteUser(again.data.user.id);
  } finally {
    await deleteUser(b);
    await admin.auth.admin.deleteUser(a.id).catch(() => {});
    await admin.from("deleted_accounts").delete().eq("id_hash", await hash(a.id));
  }
});

async function hash(text: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  return Array.from(digest, (x) => x.toString(16).padStart(2, "0")).join("");
}
