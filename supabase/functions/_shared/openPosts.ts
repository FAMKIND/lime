// Open posts (LIME-210a): the flag, and the check of a writer's signed row (signature, device certificate, master key). Phones check the same again.

import { admin } from "./db.ts";
import { fromBase64, verifyEd25519 } from "./bytes.ts";
import { HttpError } from "./http.ts";

/** What the writer's device signs: this label, a newline, then the payload text exactly as stored. */
export const OPEN_LABEL = "lime-open-post-v1\n";
export const MAX_PAYLOAD_BYTES = 200 * 1024;
export const KINDS = ["quick", "article", "record"];

export async function requireOpenPostsEnabled(): Promise<void> {
  const { data, error } = await admin().from("server_flags").select("enabled").eq("name", "open_posts_enabled").maybeSingle();
  if (error) throw new HttpError(500, "internal");
  if (!data?.enabled) throw new HttpError(403, "open_posts_disabled", "Posting to everyone is not available yet.");
}

export type Cert = { device_id: string; identity_key: string; signing_key: string; master_key: string; master_signature: string };

export type OpenPayload = {
  post_id: string; author_kind: string; author_id: string; jam_id: string; kind: string; title: string; subtitle: string; markdown: string;
  attachments: { id: string; mime: string; size?: number; name?: string }[]; topics: string[]; series?: unknown; preview_of?: string | null; has_rest?: boolean;
  version: number; created?: number;
};

function str(value: unknown, max: number): string {
  if (typeof value !== "string" || [...value].length > max) throw new HttpError(400, "bad_request", "A field is the wrong type or too long.");
  return value;
}

/** Parses the signed text and checks its shape; throws 400 for anything off. */
export function parsePayload(text: unknown): OpenPayload {
  if (typeof text !== "string" || text.length === 0 || new TextEncoder().encode(text).length > MAX_PAYLOAD_BYTES) throw new HttpError(400, "bad_request", "payload is missing or too large.");
  let p: Record<string, unknown>;
  try {
    p = JSON.parse(text);
  } catch {
    throw new HttpError(400, "bad_request", "payload is not JSON.");
  }
  const isUuid = (v: unknown) => typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
  if (!isUuid(p.post_id) || !isUuid(p.author_id) || !isUuid(p.jam_id)) throw new HttpError(400, "bad_request", "post_id, author_id and jam_id must be UUIDs.");
  if (p.author_kind !== "person") throw new HttpError(400, "bad_request", "Only a person can publish an open post here.");
  if (!KINDS.includes(String(p.kind))) throw new HttpError(400, "bad_request", "Unknown kind.");
  const attachments = Array.isArray(p.attachments) ? p.attachments : [];
  const topics = Array.isArray(p.topics) ? p.topics : [];
  if (attachments.length > 10 || topics.length > 8) throw new HttpError(400, "bad_request", "Too many files or topics.");
  for (const a of attachments) if (!isUuid((a as { id?: unknown })?.id) || typeof (a as { mime?: unknown })?.mime !== "string") throw new HttpError(400, "bad_request", "A file entry is malformed.");
  if (p.preview_of != null && !isUuid(p.preview_of)) throw new HttpError(400, "bad_request", "preview_of must be a UUID.");
  if (!Number.isInteger(p.version) || (p.version as number) < 1) throw new HttpError(400, "bad_request", "version must be a positive integer.");
  return {
    post_id: String(p.post_id).toLowerCase(), author_kind: "person", author_id: String(p.author_id).toLowerCase(), jam_id: String(p.jam_id).toLowerCase(), kind: String(p.kind),
    title: str(p.title ?? "", 120), subtitle: str(p.subtitle ?? "", 160), markdown: str(p.markdown ?? "", 100_000),
    attachments: attachments as OpenPayload["attachments"], topics: topics.map((t) => str(t, 30)), series: p.series ?? undefined,
    preview_of: p.preview_of ? String(p.preview_of).toLowerCase() : null, has_rest: p.has_rest === true, version: p.version as number,
  };
}

/**
 * The writer's own signed row: the payload names the caller as author, the device is the caller's own and not revoked, its certificate is the one the
 * server stored when it was registered (signed by the account's master key), and the device key signed `OPEN_LABEL + payload`.
 */
export async function verifyRow(me: string, payloadText: string, signature: unknown, cert: unknown): Promise<OpenPayload> {
  const payload = parsePayload(payloadText);
  if (payload.author_id !== me) throw new HttpError(403, "not_author", "You can only publish your own posts.");
  const c = cert as Cert | null;
  if (!c || typeof c !== "object" || typeof signature !== "string") throw new HttpError(400, "bad_request", "signature and cert are required.");
  const db = admin();
  const { data: device, error } = await db.from("devices").select("user_id, identity_key, signing_key, master_signature, revoked_at").eq("device_id", String(c.device_id ?? "").toLowerCase()).maybeSingle();
  if (error) throw new HttpError(500, "internal");
  if (!device || device.user_id !== me || device.revoked_at !== null) throw new HttpError(403, "bad_signature", "That device is not yours, or it was revoked.");
  const { data: master } = await db.from("master_keys").select("public_key").eq("user_id", me).maybeSingle();
  const bad = () => new HttpError(403, "bad_signature", "The signature or certificate does not verify.");
  if (!master || master.public_key !== c.master_key || device.signing_key !== c.signing_key || device.identity_key !== c.identity_key || device.master_signature !== c.master_signature) throw bad();
  const certMessage = new TextEncoder().encode(`lime-device-v1\n${String(c.device_id).toLowerCase()}\n${c.identity_key}\n${c.signing_key}`);
  try {
    if (!(await verifyEd25519(fromBase64(c.master_key), fromBase64(c.master_signature), certMessage))) throw bad();
    if (!(await verifyEd25519(fromBase64(c.signing_key), fromBase64(signature), new TextEncoder().encode(OPEN_LABEL + payloadText)))) throw bad();
  } catch (e) {
    if (e instanceof HttpError) throw e;
    throw bad();
  }
  return payload;
}

/** A 240-character plain excerpt of the markdown for the feed. */
export function excerptOf(markdown: string): string {
  return [...markdown.replace(/!\[[^\]]*\]\([^)]*\)/g, "").replace(/[#>*_`\[\]()]/g, "").replace(/\s+/g, " ").trim()].slice(0, 240).join("");
}
