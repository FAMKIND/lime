// The launch list's emails (LIME-284c2, 287a): the confirm email, the launch email and the Android email, and the batch sender. Every one carries the iOS Mail data-detector
// reset: without it Mail underlines "in 7 days" (and any date or address) as a calendar or contact link (the user's iPhone, 2026-11-07).
// The words are the user's and plot's: change them there, not here.

import { toHex } from "./bytes.ts";

export type Mail = { to: string; subject: string; text: string; html: string; headers?: Record<string, string> };

const DEFAULT_FROM = "lime <no-reply@send.limemessenger.com>";

/** CSS that stops iOS Mail turning dates, times, addresses and numbers into links (both selectors: Mail's detector and the `u + #body` Gmail/iOS trick). */
export const DETECTOR_RESET = `a[x-apple-data-detectors], u + #body a, #MessageViewBody a { color: inherit !important; text-decoration: none !important; font-size: inherit !important; font-family: inherit !important; font-weight: inherit !important; line-height: inherit !important; }`;

const esc = (s: string): string => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** A whole HTML document around some paragraphs, with the reset in its head and `id="body"` on the body. */
export function page(inner: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="x-apple-disable-message-reformatting"><meta name="format-detection" content="telephone=no, date=no, address=no, email=no, url=no"><style>${DETECTOR_RESET}</style></head>` +
    `<body id="body" style="margin:0;padding:24px;background:#f9f8f4;color:#131b17;font:16px/1.5 -apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"><div style="max-width:480px;margin:0 auto">${inner}</div></body></html>`;
}

export const button = (href: string, label: string): string =>
  `<p style="margin:20px 0"><a href="${esc(href)}" style="display:inline-block;padding:12px 22px;border-radius:999px;background:#a3e18a;color:#131b17;text-decoration:none;font-weight:600">${esc(label)}</a></p>`;

const textLink = (href: string, label: string): string => `<a href="${esc(href)}" style="color:#131b17;text-decoration:underline">${esc(label)}</a>`;

/** The confirm email (284c2, with the data-detector reset). */
export function confirmEmail(confirmUrl: string, list: "launch" | "android"): { subject: string; text: string; html: string } {
  const what = list === "android" ? "when lime is on Android" : "when lime is ready";
  return {
    subject: "Confirm your email for lime",
    text: `Tap to confirm, and we'll email you once, ${what}.\n\n${confirmUrl}\n\nDidn't ask for this? Ignore it and we'll delete your address in 7 days.`,
    html: page(`<p>Tap to confirm, and we'll email you once, ${what}.</p>${button(confirmUrl, "Confirm my email")}<p style="color:#555">Didn't ask for this? Ignore it and we'll delete your address in 7 days.</p>`),
  };
}

/** The one launch email: the App Store button, the Android option, and the promise to delete. */
export function launchEmail(to: string, links: { appStore: string; android: string; remove: string }): Mail {
  return {
    to,
    subject: "lime is here",
    text: `lime is ready. Download it on the App Store:\n${links.appStore}\n\nOn Android? Tell me when it's on Android and we'll email you once more:\n${links.android}\n\nThis is the one email we promised. We'll delete your address in 30 days, or delete it now:\n${links.remove}`,
    html: page(`<p style="font-size:20px;font-weight:600;margin:0 0 4px">lime is ready.</p><p style="margin:0">Download it on the App Store.</p>${button(links.appStore, "Download on the App Store")}` +
      `<p>On Android? ${textLink(links.android, "Tell me when it's on Android")} and we'll email you once more.</p>` +
      `<p style="color:#555">This is the one email we promised. We'll delete your address in 30 days, or ${textLink(links.remove, "delete it now")}.</p>`),
    headers: { "List-Unsubscribe": `<${links.remove}>`, "List-Unsubscribe-Post": "List-Unsubscribe=One-Click" },
  };
}

/** The Android email: said once, and the address is deleted right after. */
export function androidEmail(to: string, links: { googlePlay: string }): Mail {
  return {
    to,
    subject: "lime is on Android",
    text: `lime is on Android. Get it on Google Play:\n${links.googlePlay}\n\nWe've now deleted your address.`,
    html: page(`<p style="font-size:20px;font-weight:600;margin:0 0 4px">lime is on Android.</p><p style="margin:0">Get it on Google Play.</p>${button(links.googlePlay, "Get it on Google Play")}<p style="color:#555">We've now deleted your address.</p>`),
  };
}

/** Sends up to 100 mails in one call to Resend's batch endpoint. The `Idempotency-Key` (built from who is in it) means that if this call succeeds but the caller never records it, sending
 *  the same batch again inside 24 hours is dropped by Resend instead of double-sending. Returns the number accepted; throws on a failed call (nothing is then marked sent). */
export async function sendBatch(mails: Mail[], kind: string): Promise<number> {
  const key = Deno.env.get("LIME_NOTIFY_RESEND_API_KEY");
  if (!key) throw new Error("no mail key");
  const base = (Deno.env.get("LIME_NOTIFY_URL") ?? "https://api.resend.com/emails").replace(/\/emails$/, "");
  const from = Deno.env.get("LIME_NOTIFY_FROM") ?? DEFAULT_FROM;
  const body = mails.map((m) => ({ from, to: [m.to], subject: m.subject, text: m.text, html: m.html, ...(m.headers ? { headers: m.headers } : {}) }));
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(kind + "|" + mails.map((m) => m.to).sort().join(","))));
  const res = await fetch(`${base}/emails/batch`, {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${key}`, "Idempotency-Key": `waitlist-${kind}-${toHex(digest.slice(0, 16))}` },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(20000),
  });
  if (!res.ok) throw new Error(`mail service answered ${res.status}`);
  return mails.length;
}
