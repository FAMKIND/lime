// POST identify { identifier }: the first sign-in screen's one question. An email address says
// whether an account exists (the client then signs in or signs up); a username resolves to a
// MASKED email hint for the confirmation sheet, or 404. The username's full email is never
// returned. Unauthenticated, so rate-limited per client address.

import { admin, accountConfig, rateLimit } from "../_shared/db.ts";
import { clientIp, maskEmail, normaliseEmail, usernameError } from "../_shared/auth.ts";
import { handler, HttpError, json, readJson } from "../_shared/http.ts";

Deno.serve(handler(async (req) => {
  const body = await readJson(req);
  await rateLimit(`identify:${clientIp(req)}`, 1, accountConfig.identifyPerMinute(), 60);
  const raw = typeof body.identifier === "string" ? body.identifier.trim() : "";
  if (!raw || raw.length > 254) throw new HttpError(400, "bad_request", "Enter an email address or a username.");

  if (raw.includes("@") && !raw.startsWith("@")) {
    const email = normaliseEmail(raw);
    const { data, error } = await admin().rpc("email_account_state", { p_email: email });
    if (error) throw new HttpError(500, "internal");
    // An address that never proved itself (an unconfirmed sign-up) is still new.
    return json({ kind: "email", exists: data === "confirmed", hint: maskEmail(email) });
  }

  const username = raw.replace(/^@/, "");
  if (usernameError(username)) throw new HttpError(404, "not_found", "No account with that username.");
  const { data, error } = await admin().rpc("resolve_username", { p_username: username });
  if (error) throw new HttpError(500, "internal");
  const row = Array.isArray(data) ? data[0] : null;
  if (!row?.email) throw new HttpError(404, "not_found", "No account with that username.");
  return json({ kind: "username", hint: maskEmail(row.email) });
}));
