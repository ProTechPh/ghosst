import { ApiError, json, readJson } from "../lib/http";
import { presignGet } from "../lib/r2";
import { complete, release, reserve } from "../lib/idempotency";
import type { Ctx } from "../index";

interface ProductRef {
  id: string;
  name: string;
  cost: number;
  type: string;
}

/**
 * POST /v1/claims  (Idempotency-Key required)
 * Body: { productId, duration? }
 *
 * Same semantics as the Appwrite `claim` function, but the `crit` lock is
 * gone: a guarded UPDATE is the serialization point instead.
 *   1. charge  (atomic: WHERE coins >= cost)   ← serialization point
 *   2. assign  (oldest available key)
 *   3. record  (claims row)
 * If step 2 finds no stock, step 1 is refunded.
 */
export async function claim(ctx: Ctx): Promise<Response> {
  const uid = ctx.user!.id;
  const body = await readJson<{ productId?: string; duration?: string }>(ctx.req);
  if (!body.productId) throw new ApiError(400, "missing_product", "Missing productId");

  const idemKey = (ctx.req.headers.get("idempotency-key") ?? "").trim();
  if (!idemKey) {
    throw new ApiError(400, "missing_idempotency_key", "Idempotency-Key header required");
  }
  if (idemKey.length > 128) throw new ApiError(400, "bad_idempotency_key", "Idempotency key too long");

  const reservation = await reserve(ctx.env, uid, idemKey);
  if (reservation.state === "replay") {
    return new Response(reservation.response, {
      headers: { "content-type": "application/json; charset=utf-8" },
    });
  }
  if (reservation.state === "in_flight") {
    throw new ApiError(409, "request_in_progress", "Same request is still running — retry", 2);
  }

  try {
    const product = await ctx.env.DB.prepare(
      `SELECT id, name, cost, type FROM products WHERE id = ?1 AND active = 1`,
    )
      .bind(body.productId)
      .first<ProductRef>();
    if (!product) throw new ApiError(404, "product_not_found", "Product not found");

    const result =
      product.type === "key"
        ? await claimLicense(ctx, uid, product, (body.duration ?? "").trim())
        : await claimDownload(ctx, uid, product);

    await complete(ctx.env, uid, idemKey, result);
    return result;
  } catch (err) {
    // Free the reservation so the client's own retry is not blocked by it.
    await release(ctx.env, uid, idemKey).catch(() => {});
    throw err;
  }
}

async function claimLicense(
  ctx: Ctx,
  uid: string,
  product: ProductRef,
  durationLabel: string,
): Promise<Response> {
  let cost = product.cost;

  if (durationLabel) {
    const option = await ctx.env.DB.prepare(
      `SELECT cost FROM product_durations WHERE product_id = ?1 AND label = ?2`,
    )
      .bind(product.id, durationLabel)
      .first<{ cost: number }>();
    if (!option) throw new ApiError(400, "invalid_duration", "Invalid duration option");
    cost = option.cost;
  }

  // 1. Reserve the coins. This is the only place a balance can move down and
  //    the WHERE clause makes a negative balance impossible.
  const charged = await ctx.env.DB.prepare(
    `UPDATE users SET coins = coins - ?1 WHERE id = ?2 AND coins >= ?1 RETURNING coins`,
  )
    .bind(cost, uid)
    .first<{ coins: number }>();

  if (!charged) throw await insufficient(cost, uid, ctx);

  // 2. Oldest available key, honouring the duration pool.
  const now = new Date().toISOString();
  try {
    const picked = await ctx.env.DB.prepare(
      `UPDATE keys SET status = 'claimed', claimed_by = ?3, claimed_at = ?4
        WHERE id = (
          SELECT id FROM keys
           WHERE product_id = ?1 AND status = 'available' AND (?2 = '' OR duration = ?2)
           ORDER BY created_at LIMIT 1
        )
        AND status = 'available'
        RETURNING id, key_value`,
    )
      .bind(product.id, durationLabel, uid, now)
      .first<{ id: string; key_value: string }>();

    if (!picked) {
      throw new ApiError(
        409,
        "out_of_stock",
        durationLabel ? `Out of stock for ${durationLabel}` : "Out of stock",
      );
    }

    // 3. Record it.
    await ctx.env.DB.prepare(
      `INSERT INTO claims (id, user_id, product_id, product_name, key_id, key_text, cost, duration, created_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)`,
    )
      .bind(
        crypto.randomUUID(),
        uid,
        product.id,
        product.name,
        picked.id,
        picked.key_value,
        cost,
        durationLabel,
        now,
      )
      .run();

    return json({ ok: true, key: picked.key_value, cost, coins: charged.coins });
  } catch (err) {
    // Compensate: refund and hand the key back. Keyed on (claimed_by, claimed_at)
    // so a key taken by someone else is never released.
    await ctx.env.DB.batch([
      ctx.env.DB.prepare(`UPDATE users SET coins = coins + ?1 WHERE id = ?2`).bind(cost, uid),
      ctx.env.DB.prepare(
        `UPDATE keys SET status = 'available', claimed_by = NULL, claimed_at = NULL
          WHERE product_id = ?1 AND claimed_by = ?2 AND claimed_at = ?3`,
      ).bind(product.id, uid, now),
    ]).catch(() => {});
    throw err;
  }
}

async function claimDownload(ctx: Ctx, uid: string, product: ProductRef): Promise<Response> {
  // Single purchase: re-opening an owned item must never charge again, even
  // when the balance has since dropped below the price.
  const prior = await ctx.env.DB.prepare(
    `SELECT cost FROM claims
      WHERE user_id = ?1 AND product_id = ?2 AND object_key IS NOT NULL LIMIT 1`,
  )
    .bind(uid, product.id)
    .first<{ cost: number }>();

  const file = await ctx.env.DB.prepare(
    `SELECT object_key, filename FROM product_files WHERE product_id = ?1`,
  )
    .bind(product.id)
    .first<{ object_key: string; filename: string }>();

  if (prior) {
    if (!file) throw new ApiError(409, "download_unavailable", "Already purchased — link unavailable");
    const t = await presignGet(ctx.env, file.object_key, { filename: file.filename });
    return json({
      ok: true,
      alreadyOwned: true,
      downloadUrl: t.url,
      filename: file.filename,
      expiresIn: t.expiresIn,
      cost: prior.cost,
      coins: ctx.user!.coins,
    });
  }

  if (!file) throw new ApiError(409, "download_unavailable", "Download not configured");

  const charged = await ctx.env.DB.prepare(
    `UPDATE users SET coins = coins - ?1 WHERE id = ?2 AND coins >= ?1 RETURNING coins`,
  )
    .bind(product.cost, uid)
    .first<{ coins: number }>();

  if (!charged) throw await insufficient(product.cost, uid, ctx);

  const now = new Date().toISOString();
  let won = false;
  try {
    const inserted = await ctx.env.DB.prepare(
      `INSERT INTO claims (id, user_id, product_id, product_name, key_id, key_text, cost, object_key, created_at)
       VALUES (?1, ?2, ?3, ?4, ?5, 'app', ?6, ?7, ?8)
       ON CONFLICT DO NOTHING`,
    )
      .bind(
        crypto.randomUUID(),
        uid,
        product.id,
        product.name,
        file.object_key,
        product.cost,
        file.object_key,
        now,
      )
      .run();
    won = (inserted.meta.changes ?? 0) > 0;
  } catch (err) {
    // Charged but not recorded — give the coins back before surfacing the error.
    await ctx.env.DB.prepare(`UPDATE users SET coins = coins + ?1 WHERE id = ?2`)
      .bind(product.cost, uid)
      .run()
      .catch(() => {});
    throw err;
  }

  if (!won) {
    // Lost a race against another instance — refund and serve the existing claim.
    await ctx.env.DB.prepare(`UPDATE users SET coins = coins + ?1 WHERE id = ?2`)
      .bind(product.cost, uid)
      .run();
  }

  const t = await presignGet(ctx.env, file.object_key, { filename: file.filename });
  return json({
    ok: true,
    alreadyOwned: !won,
    downloadUrl: t.url,
    filename: file.filename,
    expiresIn: t.expiresIn,
    cost: won ? product.cost : 0,
    coins: won ? charged!.coins : ctx.user!.coins,
  });
}

async function insufficient(cost: number, uid: string, ctx: Ctx): Promise<ApiError> {
  const row = await ctx.env.DB.prepare(`SELECT coins FROM users WHERE id = ?1`)
    .bind(uid)
    .first<{ coins: number }>();
  return new ApiError(409, "insufficient_coins", `Not enough coins (need ${cost}, have ${row?.coins ?? 0})`);
}

/** GET /v1/claims — the user's own history (keys + owned downloads). */
export async function listMine(ctx: Ctx): Promise<Response> {
  const rows = await ctx.env.DB.prepare(
    `SELECT id, product_id, product_name, key_text, cost, duration, object_key, created_at
       FROM claims WHERE user_id = ?1 ORDER BY created_at DESC LIMIT 200`,
  )
    .bind(ctx.user!.id)
    .all<{
      id: string;
      product_id: string;
      product_name: string;
      key_text: string;
      cost: number;
      duration: string;
      object_key: string | null;
      created_at: string;
    }>();

  const claims = (rows.results ?? []).map((r) => ({
    id: r.id,
    productId: r.product_id,
    productName: r.product_name,
    keyText: r.key_text,
    cost: r.cost,
    duration: r.duration,
    isDownload: r.object_key != null,
    createdAt: r.created_at,
  }));

  return json({ ok: true, claims });
}
