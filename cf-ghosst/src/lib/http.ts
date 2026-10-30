export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly retryAfter?: number,
  ) {
    super(message);
  }
}

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export async function readJson<T>(req: Request): Promise<T> {
  const len = Number(req.headers.get("content-length") ?? 0);
  if (len > 1_000_000) throw new ApiError(413, "payload_too_large", "Body too large");
  try {
    return (await req.json()) as T;
  } catch {
    throw new ApiError(400, "bad_json", "Malformed JSON body");
  }
}
