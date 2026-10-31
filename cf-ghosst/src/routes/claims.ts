import { ApiError, json, readJson } from "../lib/http";
import { fileTicket } from "../lib/r2";
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
 *   1. charge + assign  (one batch = one transaction)
 *   2. record  (claims row; re-read on failure instead of refunding blindly)
 * If there is no stock, nothing is charged; if the charge is refused, the key
 * goes back.
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

  let claimed = false;
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

    claimed = true;
    try {
      await complete(ctx.env, uid, idemKey, result);
    } catch (err) {
      // The coins are gone and the goods are assigned: the claim did happen.
      // Only its replay cache is missing, so the caller still gets it.
      console.error(`[${ctx.requestId}] idempotency complete failed`, err);
    }
    return result;
  } catch (err) {
    // Free the reservation so the client's own retry is not blocked by it —
    // but never after a successful claim, or a retry would charge again.
    if (!claimed) await release(ctx.env, uid, idemKey).catch(() => {});
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

  // Pre-pick a candidate so the batch below can claim one exact row; the
  // guarded UPDATE, not this read, decides a race.
  // Two statements on purpose: with a bound `(?2 = '' OR duration = ?2)` SQLite
  // walks every available key of the product looking for a match, so a pool
  // that has run dry cost one row read per key in stock on every claim.
  const candidate = (
    durationLabel
      ? await ctx.env.DB.prepare(
          `SELECT id, key_value FROM keys
            WHERE product_id = ?1 AND status = 'available' AND duration = ?2
            ORDER BY created_at LIMIT 1`,
        )
          .bind(product.id, durationLabel)
          .first<{ id: string; key_value: string }>()
      : await ctx.env.DB.prepare(
          `SELECT id, key_value FROM keys
            WHERE product_id = ?1 AND status = 'available'
            ORDER BY created_at LIMIT 1`,
        )
          .bind(product.id)
          .first<{ id: string; key_value: string }>()
  ) as { id: string; key_value: string } | null;

  if (!candidate) throw outOfStock(durationLabel);

  const now = new Date().toISOString();

  // 1 + 2 in one transaction: the coins leave the wallet only if the key also
  // leaves the pool, so a crash can never strand either one.
  const [chargeRes, pickRes] = await ctx.env.DB.batch([
    ctx.env.DB.prepare(
      `UPDATE users SET coins = coins - ?1 WHERE id = ?2 AND coins >= ?1`,
    ).bind(cost, uid),
    ctx.env.DB.prepare(
      `UPDATE keys SET status = 'claimed', claimed_by = ?2, claimed_at = ?3
        WHERE id = ?1 AND status = 'available'`,
    ).bind(candidate.id, uid, now),
  ]);

  // The batch commits even when a WHERE matched nothing, so undo the other half.
  if ((chargeRes.meta.changes ?? 0) === 0) {
    await unclaimKey(ctx, candidate.id, uid, now);
    throw await insufficient(cost, uid, ctx);
  }
  if ((pickRes.meta.changes ?? 0) === 0) {
    await refund(ctx, uid, cost);
    throw outOfStock(durationLabel);
  }

  const wallet = await ctx.env.DB.prepare(`SELECT coins FROM users WHERE id = ?1`)
    .bind(uid)
    .first<{ coins: number }>();
  const coins = wallet?.coins ?? 0;
  const body = { ok: true, key: candidate.key_value, cost, coins };

  // 3. Record it.
  try {
    await ctx.env.DB.prepare(
      `INSERT INTO claims (id, user_id, product_id, product_name, key_id, key_text, cost, duration, created_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)`,
    )
      .bind(
        crypto.randomUUID(),
        uid,
        product.id,
        product.name,
        candidate.id,
        candidate.key_value,
        cost,
        durationLabel,
        now,
      )
      .run();
  } catch (err) {
    // The insert may have landed before the error; read it back and finish the
    // claim rather than refunding something the buyer already owns.
    const recorded = await ctx.env.DB.prepare(
      `SELECT id FROM claims WHERE user_id = ?1 AND product_id = ?2 AND key_id = ?3 LIMIT 1`,
    )
      .bind(uid, product.id, candidate.id)
      .first<{ id: string }>();

    if (recorded) return json(body);

    await ctx.env.DB.batch([
      ctx.env.DB.prepare(`UPDATE users SET coins = coins + ?1 WHERE id = ?2`).bind(cost, uid),
      ctx.env.DB.prepare(
        `UPDATE keys SET status = 'available', claimed_by = NULL, claimed_at = NULL
          WHERE id = ?1 AND claimed_by = ?2 AND claimed_at = ?3`,
      ).bind(candidate.id, uid, now),
    ]).catch(() => {});
    throw err;
  }

  return json(body);
}

function outOfStock(durationLabel: string): ApiError {
  return new ApiError(
    409,
    "out_of_stock",
    durationLabel ? `Out of stock for ${durationLabel}` : "Out of stock",
  );
}

async function refund(ctx: Ctx, uid: string, cost: number): Promise<void> {
  await ctx.env.DB.prepare(`UPDATE users SET coins = coins + ?1 WHERE id = ?2`)
    .bind(cost, uid)
    .run()
    .catch(() => {});
}

async function unclaimKey(
  ctx: Ctx,
  keyId: string,
  uid: string,
  now: string,
): Promise<void> {
  await ctx.env.DB.prepare(
    `UPDATE keys SET status = 'available', claimed_by = NULL, claimed_at = NULL
      WHERE id = ?1 AND claimed_by = ?2 AND claimed_at = ?3`,
  )
    .bind(keyId, uid, now)
    .run()
    .catch(() => {});
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
    `SELECT object_key, filename, sha256 FROM product_files WHERE product_id = ?1`,
  )
    .bind(product.id)
    .first<{ object_key: string; filename: string; sha256: string | null }>();

  if (prior) {
    if (!file) throw new ApiError(409, "download_unavailable", "Already purchased — link unavailable");
    const t = await fileTicket(ctx.env, file.object_key, file.filename);
    return json({
      ok: true,
      alreadyOwned: true,
      downloadUrl: t.url,
      filename: file.filename,
      sha256: file.sha256,
      expiresIn: t.expiresIn,
      cost: prior.cost,
      coins: ctx.user!.coins,
    });
  }

  if (!file) throw new ApiError(409, "download_unavailable", "Download not configured");

  const now = new Date().toISOString();
  const claimId = crypto.randomUUID();

  // One transaction: the purchase row and the charge land together. The insert
  // decides a race (UNIQUE user+product), the guarded UPDATE refuses an overdraft.
  const [insRes, chargeRes] = await ctx.env.DB.batch([
    ctx.env.DB.prepare(
      `INSERT INTO claims (id, user_id, product_id, product_name, key_id, key_text, cost, object_key, created_at)
       VALUES (?1, ?2, ?3, ?4, ?5, 'app', ?6, ?7, ?8)
       ON CONFLICT DO NOTHING`,
    ).bind(claimId, uid, product.id, product.name, file.object_key, product.cost, file.object_key, now),
    ctx.env.DB.prepare(
      `UPDATE users SET coins = coins - ?1 WHERE id = ?2 AND coins >= ?1`,
    ).bind(product.cost, uid),
  ]);

  const won = (insRes.meta.changes ?? 0) > 0;
  const paid = (chargeRes.meta.changes ?? 0) > 0;

  if (!paid) {
    // The batch committed, but no money moved: drop our own row if it landed.
    if (won) await ctx.env.DB.prepare(`DELETE FROM claims WHERE id = ?1`).bind(claimId).run().catch(() => {});
    throw await insufficient(product.cost, uid, ctx);
  }
  if (!won) await refund(ctx, uid, product.cost); // lost the race — serve the existing claim

  const wallet = won
    ? await ctx.env.DB.prepare(`SELECT coins FROM users WHERE id = ?1`).bind(uid).first<{ coins: number }>()
    : null;

  const t = await fileTicket(ctx.env, file.object_key, file.filename);
  return json({
    ok: true,
    alreadyOwned: !won,
    downloadUrl: t.url,
    filename: file.filename,
    sha256: file.sha256,
    expiresIn: t.expiresIn,
    cost: won ? product.cost : 0,
    coins: won ? (wallet?.coins ?? 0) : ctx.user!.coins,
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
    `SELECT c.id, c.product_id, c.product_name, c.key_text, c.cost, c.duration,
            c.object_key, c.created_at, f.sha256
       FROM claims c LEFT JOIN product_files f ON f.product_id = c.product_id
      WHERE c.user_id = ?1 ORDER BY c.created_at DESC LIMIT 200`,
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
      sha256: string | null;
    }>();

  const claims = (rows.results ?? []).map((r) => ({
    id: r.id,
    productId: r.product_id,
    productName: r.product_name,
    keyText: r.key_text,
    cost: r.cost,
    duration: r.duration,
    isDownload: r.object_key != null,
    sha256: r.object_key != null ? r.sha256 : null,
    createdAt: r.created_at,
  }));

  return json({ ok: true, claims });
}
