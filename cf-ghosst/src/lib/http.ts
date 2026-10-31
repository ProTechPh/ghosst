export class ApiError extends Error {
  // Plain fields, not constructor parameter properties: node --test strips
  // types and cannot run those.
  readonly status: number;
  readonly code: string;
  readonly retryAfter?: number;

  constructor(status: number, code: string, message: string, retryAfter?: number) {
    super(message);
    this.status = status;
    this.code = code;
    this.retryAfter = retryAfter;
  }
}

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

const MAX_BODY = 1_000_000;

export async function readJson<T>(req: Request): Promise<T> {
  const len = Number(req.headers.get("content-length") ?? 0);
  if (len > MAX_BODY) throw new ApiError(413, "payload_too_large", "Body too large");

  // A chunked body sends no content-length, so the header alone is not a cap.
  const raw = await req.text();
  if (raw.length > MAX_BODY) throw new ApiError(413, "payload_too_large", "Body too large");

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new ApiError(400, "bad_json", "Malformed JSON body");
  }

  // Every caller does `body.field`: null/42/"x"/[] would be a 500 instead.
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new ApiError(400, "bad_json", "Body must be a JSON object");
  }
  return parsed as T;
}
