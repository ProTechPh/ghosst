import { ApiError, json, readJson } from "../lib/http";
import type { Ctx } from "../index";

export async function me(ctx: Ctx): Promise<Response> {
  const row = await ctx.env.DB.prepare(
    `SELECT id, email, display_name, coins, is_admin, created_at
       FROM users WHERE id = ?1`,
  )
    .bind(ctx.user!.id)
    .first<{
      id: string;
      email: string;
      display_name: string;
      coins: number;
      is_admin: number;
      created_at: string;
    }>();
  if (!row) throw new ApiError(401, "unauthorized", "Account not found");

  return json({
    ok: true,
    user: {
      id: row.id,
      email: row.email,
      displayName: row.display_name,
      coins: row.coins,
      isAdmin: row.is_admin === 1,
      createdAt: row.created_at,
    },
  });
}

export async function wallet(ctx: Ctx): Promise<Response> {
  const [user, rewards] = await Promise.all([
    ctx.env.DB.prepare(`SELECT coins FROM users WHERE id = ?1`)
      .bind(ctx.user!.id)
      .first<{ coins: number }>(),
    ctx.env.DB.prepare(
      `SELECT id, reward, ad_unit, created_at FROM ad_rewards
        WHERE user_id = ?1 ORDER BY created_at DESC LIMIT 50`,
    )
      .bind(ctx.user!.id)
      .all<{ id: string; reward: number; ad_unit: string; created_at: string }>(),
  ]);

  return json({
    ok: true,
    coins: user?.coins ?? 0,
    rewards: (rewards.results ?? []).map((r) => ({
      id: r.id,
      reward: r.reward,
      adUnit: r.ad_unit,
      createdAt: r.created_at,
    })),
  });
}

/** Mirrors the Appwrite `deleteAccount` action, minus the lock dance. */
export async function remove(ctx: Ctx): Promise<Response> {
  const body = await readJson<{ confirm?: string }>(ctx.req);
  if (body.confirm !== "DELETE") {
    throw new ApiError(400, "confirm_required", 'Send {"confirm":"DELETE"} to confirm');
  }

  const uid = ctx.user!.id;
  const now = new Date().toISOString();

  await ctx.env.DB.batch([
    ctx.env.DB.prepare(`DELETE FROM claims WHERE user_id = ?1`).bind(uid),
    // ad_rewards rows deliberately survive: they hold only a transaction id, the
    // tombstone user id, an email hash and a timestamp — no PII — and they are
    // what keeps the daily ad cap from resetting on a delete + re-register.
    ctx.env.DB.prepare(`DELETE FROM idempotency WHERE user_id = ?1`).bind(uid),
    // Back to the shelf: leaving status = 'claimed' would strand the key forever.
    ctx.env.DB.prepare(
      `UPDATE keys SET status = 'available', claimed_by = NULL, claimed_at = NULL
        WHERE claimed_by = ?1`,
    ).bind(uid),
    // Anonymise rather than keep the PII: the row stays as a tombstone so the
    // id never gets reused, but the email/password are gone for good.
    ctx.env.DB.prepare(
      `UPDATE users SET deleted_at = ?1,
         email = 'deleted+' || ?2 || '@invalid',
         display_name = '',
         password_hash = ''
       WHERE id = ?2`,
    ).bind(now, uid),
    ctx.env.DB.prepare(`UPDATE sessions SET revoked_at = ?1 WHERE user_id = ?2`).bind(now, uid),
  ]);

  return json({ ok: true });
}
