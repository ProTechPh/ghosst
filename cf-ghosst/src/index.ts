import { ApiError, json } from "./lib/http";
import { corsHeaders } from "./lib/cors";
import { requireUser, type AuthUser } from "./lib/auth";
import * as auth from "./routes/auth";
import * as account from "./routes/account";
import * as products from "./routes/products";
import * as keys from "./routes/keys";
import * as claims from "./routes/claims";
import * as ads from "./routes/ads";
import * as uploads from "./routes/uploads";
import * as downloads from "./routes/downloads";

export interface Ctx {
  req: Request;
  env: Env;
  url: URL;
  requestId: string;
  params: Record<string, string>;
  user: AuthUser | null;
}

type AuthMode = "none" | "required" | "optional";
type Handler = (ctx: Ctx) => Promise<Response>;

interface Route {
  method: string;
  pattern: RegExp;
  handler: Handler;
  auth: AuthMode;
}

const routes: Route[] = [
  { method: "POST", pattern: /^\/v1\/auth\/register$/, handler: auth.register, auth: "none" },
  { method: "POST", pattern: /^\/v1\/auth\/login$/, handler: auth.login, auth: "none" },
  { method: "POST", pattern: /^\/v1\/auth\/refresh$/, handler: auth.refresh, auth: "none" },
  { method: "POST", pattern: /^\/v1\/auth\/logout$/, handler: auth.logout, auth: "required" },

  { method: "GET", pattern: /^\/v1\/me$/, handler: account.me, auth: "required" },
  { method: "GET", pattern: /^\/v1\/wallet$/, handler: account.wallet, auth: "required" },
  { method: "DELETE", pattern: /^\/v1\/account$/, handler: account.remove, auth: "required" },

  { method: "GET", pattern: /^\/v1\/products$/, handler: products.list, auth: "optional" },
  { method: "GET", pattern: /^\/v1\/products\/([\w.-]+)$/, handler: products.get, auth: "optional" },
  { method: "POST", pattern: /^\/v1\/products$/, handler: products.create, auth: "required" },
  { method: "PATCH", pattern: /^\/v1\/products\/([\w.-]+)$/, handler: products.update, auth: "required" },
  { method: "DELETE", pattern: /^\/v1\/products\/([\w.-]+)$/, handler: products.remove, auth: "required" },

  { method: "POST", pattern: /^\/v1\/admin\/keys$/, handler: keys.add, auth: "required" },
  { method: "GET", pattern: /^\/v1\/admin\/keys$/, handler: keys.list, auth: "required" },
  { method: "DELETE", pattern: /^\/v1\/admin\/keys\/([\w.-]+)$/, handler: keys.remove, auth: "required" },
  {
    method: "DELETE",
    pattern: /^\/v1\/admin\/products\/([\w.-]+)\/keys$/,
    handler: keys.clearForProduct,
    auth: "required",
  },

  { method: "POST", pattern: /^\/v1\/claims$/, handler: claims.claim, auth: "required" },
  { method: "GET", pattern: /^\/v1\/claims$/, handler: claims.listMine, auth: "required" },

  { method: "POST", pattern: /^\/v1\/uploads\/presign$/, handler: uploads.presign, auth: "required" },
  { method: "POST", pattern: /^\/v1\/uploads\/complete$/, handler: uploads.complete, auth: "required" },
  { method: "GET", pattern: /^\/v1\/downloads\/([\w.-]+)$/, handler: downloads.ticket, auth: "required" },

  // Google calls this one: no JWT, signature-verified instead.
  { method: "GET", pattern: /^\/v1\/ads\/ssv$/, handler: ads.ssv, auth: "none" },
];

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    const cors = corsHeaders(req, env);
    const requestId = req.headers.get("x-request-id") ?? crypto.randomUUID();

    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    const withCors = (res: Response): Response => {
      const headers = new Headers(res.headers);
      cors.forEach((v, k) => headers.set(k, v));
      headers.set("x-request-id", requestId);
      return new Response(res.body, { status: res.status, headers });
    };

    const route = routes.find((r) => r.method === req.method && r.pattern.test(url.pathname));
    if (!route) {
      return withCors(
        json(
          { ok: false, error: { code: "not_found", message: "No such route", requestId } },
          404,
        ),
      );
    }

    const match = route.pattern.exec(url.pathname) ?? [];
    const ctx: Ctx = {
      req,
      env,
      url,
      requestId,
      params: { id: match[1] ?? "" },
      user: null,
    };

    try {
      if (route.auth === "required") {
        ctx.user = await requireUser(ctx);
      } else if (route.auth === "optional" && req.headers.has("authorization")) {
        ctx.user = await requireUser(ctx).catch(() => null);
      }

      const res = await route.handler(ctx);

      // Public product reads are safe to cache at the edge; anything authed is not.
      if (
        req.method === "GET" &&
        url.pathname.startsWith("/v1/products") &&
        res.status === 200 &&
        !req.headers.has("authorization")
      ) {
        res.headers.set("cache-control", "public, max-age=30, stale-while-revalidate=120");
      }

      return withCors(res);
    } catch (err) {
      if (err instanceof ApiError) {
        const res = json(
          { ok: false, error: { code: err.code, message: err.message, requestId } },
          err.status,
        );
        if (err.retryAfter) res.headers.set("retry-after", String(err.retryAfter));
        return withCors(res);
      }

      console.error(`[${requestId}] ${req.method} ${url.pathname}`, err);
      return withCors(
        json(
          {
            ok: false,
            error: {
              code: "internal",
              message: "Something went wrong on our side",
              requestId,
            },
          },
          500,
        ),
      );
    }
  },
};
