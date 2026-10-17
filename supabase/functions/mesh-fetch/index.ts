// POST mesh-fetch { request }: relay download (LIME-155). An OFFLINE phone asks a nearby ONLINE lime phone to fetch its mail for it. The offline phone
// builds a request, signs it with its own device key, seals it to this server's mesh public key and hands it over Bluetooth; the neighbour posts it
// here and passes the reply back, which only the offline phone can read.
//
// **No session, on purpose.** The caller is the relay and the server must not learn which account relayed for whom: the device's own Ed25519
// signature over the request is the authorisation (the same `devices.signing_key` `devices-register` stored), with a single-use nonce and an
// expiry of at most 10 minutes. Only the anon `apikey` header (as for any public function) arrives with it; a session header, if one is sent anyway,
// is never read.
//
// Limits: per target device (6 a minute) and per caller address, as a KEYED HASH bucket (`_shared/ipbucket.ts`: never the address). Every refusal
// is the same opaque 403; the reason code goes to the function logs with no device, account, address or token in it. The reply is the
// `mailbox-fetch` item shape, encrypted to the request's `reply_key` and padded to 4 KiB steps, so the relay sees only a bucket size.
//
// What each party learns: the relay: an opaque request and an opaque padded reply (not whose mail, not how many items beyond the size bucket).
// The server: that device D's mail was fetched at time t from some address, which is what it learns when D fetches for itself; NOT which
// account relayed. The relay's address is the honest remaining limit (a keyed hash of it is rate-limited for a day, nothing more).

import { admin, config, rateLimit } from "../_shared/db.ts";
import { fromBase64, fromPgBytea, sha256, toBase64, toHex, verifyEd25519 } from "../_shared/bytes.ts";
import { accessDenied } from "../_shared/access.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";
import { FETCH_SIGN_LABEL, openFetchRequest, parseFetchRequest, routingKeysFromEnv, sealFetchReply } from "../_shared/mesh.ts";
import { ipBucket } from "../_shared/ipbucket.ts";

/** What a reply may hold before it is padded: it must fit one Bluetooth frame (80 KiB) with room to spare. */
const REPLY_BUDGET_BYTES = 48 * 1024;
const MAX_REQUEST_LIFE_SECONDS = 600;

async function limit(bucket: string, cost: number, max: number, windowSeconds: number) {
  try {
    await rateLimit(bucket, cost, max, windowSeconds);
  } catch (error) {
    if (error instanceof HttpError && error.status === 429) throw accessDenied("rate_limited");
    throw error;
  }
}

Deno.serve(handler(async (req) => {
  const keys = routingKeysFromEnv();
  if (keys.size === 0) throw new HttpError(503, "not_configured", "The mesh is not set up on this server yet.");
  const body = await readJson(req, 8 * 1024);
  let sealed: Uint8Array;
  try {
    sealed = fromBase64(String(body.request));
    if (sealed.length === 0 || sealed.length > 1024) throw new Error();
  } catch {
    throw new HttpError(400, "bad_request", "request must be base64 and not empty or too large.");
  }
  // Before any cryptography: the caller's address, as a keyed-hash bucket.
  await limit(await ipBucket(req, "mesh-fetch"), 1, 30, 60);

  const opened = await openFetchRequest(keys, sealed);
  if (!opened) throw accessDenied("fetch_unopenable");
  const parsed = parseFetchRequest(opened);
  if (!parsed || !(parsed.after >= 0) || !(parsed.ackThrough >= -1) || parsed.limit < 1) throw accessDenied("fetch_fields");
  const now = Math.floor(Date.now() / 1000);
  if (parsed.expiresAt <= now || parsed.expiresAt > now + MAX_REQUEST_LIFE_SECONDS) throw accessDenied("fetch_expired");

  const db = admin();
  const { data: device } = await db.from("devices").select("device_id, signing_key, revoked_at").eq("device_id", parsed.deviceId).maybeSingle();
  if (!device || device.revoked_at !== null) throw accessDenied("fetch_device");
  const signed = new Uint8Array(FETCH_SIGN_LABEL.length + parsed.canonical.length);
  signed.set(FETCH_SIGN_LABEL, 0);
  signed.set(parsed.canonical, FETCH_SIGN_LABEL.length);
  let publicKey: Uint8Array;
  try {
    publicKey = fromBase64(device.signing_key as string);
  } catch {
    throw accessDenied("fetch_signature");
  }
  if (!(await verifyEd25519(publicKey, parsed.signature, signed))) throw accessDenied("fetch_signature");

  // Only a request that is really the device's counts against the device's limit (a forger cannot burn it).
  await limit(`mesh-fetch:dev:${toHex((await sha256(new TextEncoder().encode(parsed.deviceId))).slice(0, 12))}`, 1, 6, 60);

  // Single use: the nonce is kept until the request expires, then forgotten. Nothing else is stored.
  await db.from("mesh_fetch_nonces").delete().lt("expires_at", new Date().toISOString());
  const { error: nonceError } = await db.from("mesh_fetch_nonces").insert({ nonce: "\\x" + toHex(parsed.nonce), expires_at: new Date(parsed.expiresAt * 1000).toISOString() });
  if (nonceError) {
    if (nonceError.code === "23505") throw accessDenied("nonce_used");
    console.error("mesh-fetch: nonce store failed", nonceError.code);
    throw new HttpError(500, "internal");
  }

  // The acknowledgement of what the phone has already kept, exactly as `mailbox-ack`.
  if (parsed.ackThrough >= 0) {
    const { error } = await db.from("mailbox_items").delete().eq("to_device", parsed.deviceId).lte("cursor", parsed.ackThrough);
    if (error) {
      console.error("mesh-fetch: ack failed", error.code);
      throw new HttpError(500, "internal");
    }
  }

  const maxItems = config.maxItemsPerFetch();
  const wanted = Math.min(parsed.limit, maxItems);
  const { data, error } = await db
    .from("mailbox_items")
    .select("cursor, ciphertext, size, received_at, identified, sender_user")
    .eq("to_device", parsed.deviceId)
    .gt("cursor", parsed.after)
    .order("cursor", { ascending: true })
    .limit(wanted + 1);
  if (error) {
    console.error("mesh-fetch: read failed", error.code);
    throw new HttpError(500, "internal");
  }
  const rows = data ?? [];

  // A prefix of the items, never a gap (the acknowledgement deletes everything up to a cursor): as many as fit the budget.
  const items: unknown[] = [];
  let size = 64;
  let blocked = false;
  for (const r of rows.slice(0, wanted)) {
    const item = {
      cursor: r.cursor,
      ciphertext: toBase64(fromPgBytea(r.ciphertext as string)),
      size: r.size,
      received_at: r.received_at,
      ...(r.identified ? { identified: true, sender_user: r.sender_user } : {}),
    };
    const cost = JSON.stringify(item).length + 1;
    if (size + cost > REPLY_BUDGET_BYTES) {
      // The first one alone does not fit one Bluetooth frame: say so, the phone fetches it over the internet.
      if (items.length === 0) blocked = true;
      break;
    }
    items.push(item);
    size += cost;
  }
  const hasMore = items.length < Math.min(rows.length, wanted) || rows.length > wanted;
  const reply = await sealFetchReply(parsed.replyKey, new TextEncoder().encode(JSON.stringify({ items, has_more: hasMore, ...(blocked ? { blocked: true } : {}) })));
  return json({ reply: toBase64(reply) });
}));
