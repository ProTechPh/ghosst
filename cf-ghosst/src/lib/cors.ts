const DEFAULT_ORIGINS = "https://ghosst.app,https://app.ghosst.app";

/**
 * Bearer tokens only (no cookies), so "*" is safe — but we echo a known
 * origin when we recognise it so the response stays cache-friendly.
 * Android/iOS native HTTP ignores CORS entirely; this is for Flutter Web,
 * the AdMob console verify button, and browser tooling.
 */
export function corsHeaders(req: Request, env: Env): Headers {
  const h = new Headers();
  const origin = req.headers.get("origin") ?? "";
  const allowed = (env.ALLOWED_ORIGINS ?? DEFAULT_ORIGINS)
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  if (origin && allowed.includes(origin)) {
    h.set("access-control-allow-origin", origin);
    h.set("vary", "origin");
  } else if (!origin) {
    h.set("access-control-allow-origin", "*");
  }

  h.set("access-control-allow-methods", "GET, POST, PATCH, DELETE, OPTIONS");
  h.set(
    "access-control-allow-headers",
    req.headers.get("access-control-request-headers") ??
      "authorization, content-type, idempotency-key, x-request-id",
  );
  h.set("access-control-expose-headers", "x-request-id, retry-after");
  h.set("access-control-max-age", "86400");
  return h;
}
