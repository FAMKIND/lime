// A short notice emailed to an account. It goes through Resend's HTTP API with a key kept as a
// function secret (LIME_NOTIFY_RESEND_API_KEY, never in the repo); without the secret nothing is
// sent and nothing fails. It is best effort: a failed send never blocks what triggered it.

const DEFAULT_FROM = "Lime <no-reply@send.limechat.org>";

export type Notice = { subject: string; text: string; html: string };

/** The notice for an account whose master key was just replaced. */
export function keysReplacedNotice(when = new Date()): Notice {
  const text = "A new phone signed in and replaced your Lime keys. If this wasn't you, reset your password.";
  const detail = "Your chats on your other phones stop working until you sign in there again, and your contacts will be asked to accept your new key.";
  const stamp = when.toISOString().replace("T", " ").replace(/\.\d+Z$/, " UTC");
  return {
    subject: "A new phone signed in to Lime",
    text: `${text}\n\n${detail}\n\n${stamp}`,
    html: `<p>${text}</p><p>${detail}</p><p style="color:#666">${stamp}</p>`,
  };
}

/** Sends a notice. Returns true when it was handed to the mail service. */
export async function sendNotice(to: string, notice: Notice): Promise<boolean> {
  const key = Deno.env.get("LIME_NOTIFY_RESEND_API_KEY");
  if (!key) return false;
  const url = Deno.env.get("LIME_NOTIFY_URL") ?? "https://api.resend.com/emails";
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
      body: JSON.stringify({ from: Deno.env.get("LIME_NOTIFY_FROM") ?? DEFAULT_FROM, to: [to], ...notice }),
      signal: AbortSignal.timeout(4000),
    });
    if (!res.ok) console.error("notice not sent", res.status);
    return res.ok;
  } catch {
    console.error("notice not sent: unreachable");
    return false;
  }
}
