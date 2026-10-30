import { ApiError } from "./http";
import type { Ctx } from "../index";

export interface AuthUser {
  id: string;
  email: string;
  coins: number;
  isAdmin: boolean;
}

const encoder = new TextEncoder();
const KEY_CACHE = new Map<string, CryptoKey>();

export function b64urlEncode(bytes: Uint8Array | ArrayBuffer): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let bin = "";
  for (const b of view) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function b64urlDecode(s: string): Uint8Array {
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function hmacKey(secret: string, usage: "sign" | "verify"): Promise<CryptoKey> {
  const cacheKey = `${usage}:${secret}`;
  const cached = KEY_CACHE.get(cacheKey);
  if (cached) return cached;
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    [usage],
  );
  KEY_CACHE.set(cacheKey, key);
  return key;
}

export interface AccessClaims {
  sub: string;
  adm: number;
  sid: string;
  iat: number;
  exp: number;
}

export async function signAccessToken(
  claims: Omit<AccessClaims, "iat" | "exp">,
  secret: string,
  ttlSeconds = 900,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const payload: AccessClaims = { ...claims, iat: now, exp: now + ttlSeconds };
  const head = b64urlEncode(encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const body = b64urlEncode(encoder.encode(JSON.stringify(payload)));
  const data = `${head}.${body}`;
  const sig = await crypto.subtle.sign("HMAC", await hmacKey(secret, "sign"), encoder.encode(data));
  return `${data}.${b64urlEncode(sig)}`;
}

export async function verifyAccessToken(
  token: string,
  secret: string,
): Promise<AccessClaims | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [head, body, sig] = parts;

  const valid = await crypto.subtle.verify(
    "HMAC",
    await hmacKey(secret, "verify"),
    b64urlDecode(sig),
    encoder.encode(`${head}.${body}`),
  );
  if (!valid) return null;

  try {
    const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(body))) as AccessClaims;
    if (!claims.sub || !claims.exp || claims.exp * 1000 < Date.now()) return null;
    return claims;
  } catch {
    return null;
  }
}

// shortcut: 100k PBKDF2 iterations fits the Free plan's 10ms CPU budget.
// Raise to 600k if the account moves to Workers Paid.
const PBKDF2_ITERATIONS = 100_000;

export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations: PBKDF2_ITERATIONS },
    await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]),
    256,
  );
  return `pbkdf2$${PBKDF2_ITERATIONS}$${b64urlEncode(salt)}$${b64urlEncode(bits)}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [scheme, iter, saltB64, hashB64] = stored.split("$");
  if (scheme !== "pbkdf2" || !iter || !saltB64 || !hashB64) return false;
  const iterations = Number(iter);
  if (!Number.isFinite(iterations) || iterations <= 0) return false;

  const bits = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      hash: "SHA-256",
      salt: b64urlDecode(saltB64),
      iterations,
    },
    await crypto.subtle.importKey("raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]),
    256,
  );
  return constantTimeEqual(b64urlEncode(bits), hashB64);
}

export function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export function randomToken(bytes = 32): string {
  return b64urlEncode(crypto.getRandomValues(new Uint8Array(bytes)));
}

export async function sha256Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(input));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Reads the bearer token and loads the live user row (fresh coins/isAdmin). */
export async function requireUser(ctx: Ctx): Promise<AuthUser> {
  const header = ctx.req.headers.get("authorization") ?? "";
  const token = header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : "";
  if (!token) throw new ApiError(401, "unauthorized", "Missing bearer token");

  const claims = await verifyAccessToken(token, ctx.env.JWT_SECRET);
  if (!claims) throw new ApiError(401, "unauthorized", "Invalid or expired token");

  const row = await ctx.env.DB.prepare(
    `SELECT id, email, coins, is_admin FROM users WHERE id = ?1 AND deleted_at IS NULL`,
  )
    .bind(claims.sub)
    .first<{ id: string; email: string; coins: number; is_admin: number }>();

  if (!row) throw new ApiError(401, "unauthorized", "Account not found");
  return { id: row.id, email: row.email, coins: row.coins, isAdmin: row.is_admin === 1 };
}

export function requireAdmin(ctx: Ctx): AuthUser {
  if (!ctx.user?.isAdmin) throw new ApiError(403, "forbidden", "Admin only");
  return ctx.user;
}
