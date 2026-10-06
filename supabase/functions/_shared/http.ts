// Small HTTP helpers. Nothing in here logs request bodies, keys, ciphertext or tokens.

export class HttpError extends Error {
  constructor(public status: number, public code: string, message?: string) {
    super(message ?? code);
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
}

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) return json({ error: error.code, message: error.message }, error.status);
  // Do not echo or log internals: they may contain request data.
  return json({ error: "internal", message: "Something went wrong." }, 500);
}

export async function readJson(req: Request, maxBytes = 256 * 1024): Promise<Record<string, unknown>> {
  if (req.method !== "POST") throw new HttpError(405, "method_not_allowed", "Use POST.");
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > maxBytes) throw new HttpError(413, "too_large", "The request is too large.");
  const text = await req.text();
  if (text.length > maxBytes) throw new HttpError(413, "too_large", "The request is too large.");
  try {
    const value = JSON.parse(text);
    if (value === null || typeof value !== "object" || Array.isArray(value)) throw new Error("not an object");
    return value as Record<string, unknown>;
  } catch {
    throw new HttpError(400, "bad_request", "The body must be a JSON object.");
  }
}

/** Wraps a handler so every error becomes a clean JSON response. */
export function handler(fn: (req: Request) => Promise<Response>): (req: Request) => Promise<Response> {
  return async (req) => {
    try {
      return await fn(req);
    } catch (error) {
      return errorResponse(error);
    }
  };
}
