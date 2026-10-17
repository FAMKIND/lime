// A rate-limit bucket for a caller's network address that never holds the address (LIME-155, 157): a keyed hash of it, so the rate-limit table
// cannot be turned back into who connected from where. The key is the server's mesh secret. The address is read, hashed and dropped: it is never
// logged, never stored with a device or an account, and the bucket row is swept after a day with the other rate-limit rows.

import { clientIp } from "./auth.ts";
import { toHex } from "./bytes.ts";
import { routingKeysFromEnv } from "./mesh.ts";

export async function ipBucket(req: Request, label: string): Promise<string> {
  const keys = routingKeysFromEnv();
  const secret = [...keys.entries()].sort((a, b) => a[0] - b[0]).pop()?.[1] ?? "no-key";
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${label}|${clientIp(req)}`)));
  return `${label}:ip:${toHex(mac.slice(0, 12))}`;
}
