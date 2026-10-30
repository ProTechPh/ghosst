import { ApiError, json, readJson } from "../lib/http";
import {
  b64urlEncode,
  hashPassword,
  randomToken,
  sha256Hex,
  signAccessToken,
  verifyPassword,
} from "../lib/auth";
import type { Ctx } from "../index";

// 1 h: every refresh costs 2 row writes, and on the Free plan the daily budget
// for those is 100k — a 15 min token spent it on idle users, not on claims.
const ACCESS_TTL = 3600;
const REFRESH_TTL_MS = 60 * 24 * 60 * 60 * 1000; // 60 days

interface Credentials {
  email?: string;
  password?: string;
  displayName?: string;
}

interface UserRow {
  id: string;
  email: string;
  coins: number;
  is_admin: number;
}

export async function register(ctx: Ctx): Promise<Response> {
  const body = await readJson<Credentials>(ctx.req);
  const email = (body.email ?? "").trim().toLowerCase();
  const password = body.password ?? "";
  const displayName = (body.displayName ?? "").trim().slice(0, 128);

  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw new ApiError(400, "invalid_email", "That email doesn't look right");
  }
  if (password.length < 8) {
    throw new ApiError(400, "weak_password", "Password must be at least 8 characters");
  }

  const taken = await ctx.env.DB.prepare(
    `SELECT id FROM users WHERE email = ?1 AND deleted_at IS NULL`,
  )
    .bind(email)
    .first<{ id: string }>();
  if (taken) throw new ApiError(409, "email_taken", "That email is already registered");

  const id = crypto.randomUUID();
  await ctx.env.DB.prepare(
    `INSERT INTO users (id, email, password_hash, display_name, created_at)
     VALUES (?1, ?2, ?3, ?4, ?5)`,
  )
    .bind(id, email, await hashPassword(password), displayName, new Date().toISOString())
    .run();

  return issueSession(ctx, { id, email, coins: 0, is_admin: 0 });
}

export async function login(ctx: Ctx): Promise<Response> {
  const body = await readJson<Credentials>(ctx.req);
  const email = (body.email ?? "").trim().toLowerCase();
  const password = body.password ?? "";

  const user = await ctx.env.DB.prepare(
    `SELECT id, email, coins, is_admin, password_hash FROM users
      WHERE email = ?1 AND deleted_at IS NULL`,
  )
    .bind(email)
    .first<UserRow & { password_hash: string }>();

  if (!user) {
    // Same work as a real check so response timing doesn't leak which emails exist.
    await hashPassword(password);
    throw new ApiError(401, "invalid_credentials", "Wrong email or password");
  }
  if (!(await verifyPassword(password, user.password_hash))) {
    throw new ApiError(401, "invalid_credentials", "Wrong email or password");
  }

  return issueSession(ctx, user);
}

export async function refresh(ctx: Ctx): Promise<Response> {
  const body = await readJson<{ refreshToken?: string }>(ctx.req);
  const presented = body.refreshToken ?? "";
  if (!presented) throw new ApiError(401, "unauthorized", "Missing refresh token");

  const hash = await sha256Hex(presented);
  const row = await ctx.env.DB.prepare(
    `SELECT s.id, s.user_id, s.family, s.expires_at, s.revoked_at,
            u.email, u.coins, u.is_admin
       FROM sessions s JOIN users u ON u.id = s.user_id
      WHERE s.refresh_hash = ?1 AND u.deleted_at IS NULL`,
  )
    .bind(hash)
    .first<{
      id: string;
      user_id: string;
      family: string;
      expires_at: string;
      revoked_at: string | null;
      email: string;
      coins: number;
      is_admin: number;
    }>();

  if (!row) throw new ApiError(401, "unauthorized", "Unknown refresh token");

  if (row.revoked_at) {
    // A replay inside the grace window is usually the client retrying after a
    // dropped response, not a stolen token: refuse it without nuking every
    // session the user has. Outside the window, assume the token leaked.
    const revokedMsAgo = Date.now() - Date.parse(row.revoked_at);
    if (!(revokedMsAgo >= 0 && revokedMsAgo <= 60_000)) {
      await ctx.env.DB.prepare(
        `UPDATE sessions SET revoked_at = ?1 WHERE family = ?2 AND revoked_at IS NULL`,
      )
        .bind(new Date().toISOString(), row.family)
        .run();
    }
    throw new ApiError(401, "unauthorized", "Session revoked — sign in again");
  }

  if (Date.parse(row.expires_at) < Date.now()) {
    throw new ApiError(401, "unauthorized", "Session expired — sign in again");
  }

  await ctx.env.DB.prepare(`UPDATE sessions SET revoked_at = ?1 WHERE id = ?2`)
    .bind(new Date().toISOString(), row.id)
    .run();

  return issueSession(
    ctx,
    { id: row.user_id, email: row.email, coins: row.coins, is_admin: row.is_admin },
    row.family,
  );
}

export async function logout(ctx: Ctx): Promise<Response> {
  const body = await readJson<{ refreshToken?: string }>(ctx.req).catch(
    (): { refreshToken?: string } => ({}),
  );
  const presented = body.refreshToken ?? "";
  if (presented) {
    await ctx.env.DB.prepare(
      `UPDATE sessions SET revoked_at = ?1 WHERE refresh_hash = ?2 AND user_id = ?3`,
    )
      .bind(new Date().toISOString(), await sha256Hex(presented), ctx.user!.id)
      .run();
  } else {
    await ctx.env.DB.prepare(
      `UPDATE sessions SET revoked_at = ?1 WHERE user_id = ?2 AND revoked_at IS NULL`,
    )
      .bind(new Date().toISOString(), ctx.user!.id)
      .run();
  }
  return json({ ok: true });
}

async function issueSession(
  ctx: Ctx,
  user: { id: string; email: string; coins: number; is_admin: number },
  family = crypto.randomUUID(),
): Promise<Response> {
  const sessionId = crypto.randomUUID();
  const refreshToken = randomToken(32);
  const now = new Date();

  await ctx.env.DB.prepare(
    `INSERT INTO sessions (id, user_id, refresh_hash, family, user_agent, created_at, expires_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`,
  )
    .bind(
      sessionId,
      user.id,
      await sha256Hex(refreshToken),
      family,
      (ctx.req.headers.get("user-agent") ?? "").slice(0, 200),
      now.toISOString(),
      new Date(now.getTime() + REFRESH_TTL_MS).toISOString(),
    )
    .run();

  const accessToken = await signAccessToken(
    { sub: user.id, adm: user.is_admin, sid: sessionId },
    ctx.env.JWT_SECRET,
    ACCESS_TTL,
  );

  return json({
    ok: true,
    accessToken,
    refreshToken,
    accessExpiresIn: ACCESS_TTL,
    user: {
      id: user.id,
      email: user.email,
      coins: user.coins,
      isAdmin: user.is_admin === 1,
    },
  });
}

export { b64urlEncode };
