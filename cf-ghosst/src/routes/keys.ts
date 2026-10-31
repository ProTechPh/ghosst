import { ApiError, json, readJson } from "../lib/http";
import { requireAdmin } from "../lib/auth";
import type { Ctx } from "../index";

// D1 caps a statement at 100 bound parameters; 5 per row -> 20 rows.
const ROWS_PER_STATEMENT = 20;
const STATEMENTS_PER_BATCH = 50;

/** POST /v1/admin/keys — bulk paste, deduped by the UNIQUE(product_id, key_value) index. */
export async function add(ctx: Ctx): Promise<Response> {
  requireAdmin(ctx);
  const body = await readJson<{ productId?: string; keys?: string[]; duration?: string }>(ctx.req);
  const productId = body.productId ?? "";
  if (!productId) throw new ApiError(400, "invalid_product", "productId is required");

  const duration = (body.duration ?? "").trim().slice(0, 64);
  const values = [...new Set((body.keys ?? []).map((k) => k.trim()).filter(Boolean))];
  if (values.length === 0) throw new ApiError(400, "no_keys", "No keys to add");
  if (values.length > 20_000) throw new ApiError(413, "too_many_keys", "Max 20,000 keys per request");

  const product = await ctx.env.DB.prepare(`SELECT id FROM products WHERE id = ?1`)
    .bind(productId)
    .first<{ id: string }>();
  if (!product) throw new ApiError(404, "product_not_found", "Product not found");

  const statements: D1PreparedStatement[] = [];
  for (let i = 0; i < values.length; i += ROWS_PER_STATEMENT) {
    const chunk = values.slice(i, i + ROWS_PER_STATEMENT);
    const tuples = chunk
      .map((_, j) => `(?${j * 5 + 1}, ?${j * 5 + 2}, ?${j * 5 + 3}, 'available', ?${j * 5 + 4}, ?${j * 5 + 5})`)
      .join(",");
    statements.push(
      ctx.env.DB.prepare(
        `INSERT INTO keys (id, product_id, key_value, status, duration, created_at)
         VALUES ${tuples}
         ON CONFLICT(product_id, key_value) DO NOTHING`,
      ).bind(
        ...chunk.flatMap((key) => [
          crypto.randomUUID(),
          productId,
          key,
          duration,
          new Date().toISOString(),
        ]),
      ),
    );
  }

  let added = 0;
  for (let i = 0; i < statements.length; i += STATEMENTS_PER_BATCH) {
    const results = await ctx.env.DB.batch(statements.slice(i, i + STATEMENTS_PER_BATCH));
    added += results.reduce((sum, r) => sum + (r.meta.changes ?? 0), 0);
  }

  return json({
    ok: true,
    submitted: values.length,
    added,
    skipped: values.length - added,
  });
}

/**
 * GET /v1/admin/keys?productId=&status=available&limit=500
 * GET /v1/admin/keys?productId=&status=available&count=1 -> { total }
 *
 * Filters are concatenated, not written as `(?1 = '' OR col = ?1)`: that shape
 * makes SQLite scan the whole table, and rows read is the D1 free-plan budget.
 */
export async function list(ctx: Ctx): Promise<Response> {
  requireAdmin(ctx);
  const productId = ctx.url.searchParams.get("productId") ?? "";
  const status = ctx.url.searchParams.get("status") ?? "";
  const limit = Math.min(Number(ctx.url.searchParams.get("limit") ?? 500) || 500, 5000);

  const filters: string[] = [];
  const params: string[] = [];
  if (productId) {
    params.push(productId);
    filters.push(`product_id = ?${params.length}`);
  }
  if (status) {
    params.push(status);
    filters.push(`status = ?${params.length}`);
  }
  // Count-only: how many keys sit in one duration pool.
  if (ctx.url.searchParams.get("count") === "1") {
    const duration = ctx.url.searchParams.get("duration") ?? "";
    if (duration) {
      params.push(duration);
      filters.push(`duration = ?${params.length}`);
    }
  }
  const where = filters.length ? `WHERE ${filters.join(" AND ")}` : "";

  if (ctx.url.searchParams.get("count") === "1") {
    const row = await ctx.env.DB.prepare(`SELECT COUNT(*) AS n FROM keys ${where}`)
      .bind(...params)
      .first<{ n: number }>();
    return json({ ok: true, total: row?.n ?? 0 });
  }

  const rows = await ctx.env.DB.prepare(
    `SELECT id, product_id, key_value, status, duration, claimed_by, claimed_at, created_at
       FROM keys
       ${where}
      ORDER BY created_at
      LIMIT ?${params.length + 1}`,
  )
    .bind(...params, limit)
    .all<{
      id: string;
      product_id: string;
      key_value: string;
      status: string;
      duration: string;
      claimed_by: string | null;
      claimed_at: string | null;
      created_at: string;
    }>();

  const keys = (rows.results ?? []).map((r) => ({
    id: r.id,
    productId: r.product_id,
    key: r.key_value,
    status: r.status,
    duration: r.duration,
    claimedBy: r.claimed_by,
    claimedAt: r.claimed_at,
    createdAt: r.created_at,
  }));

  return json({ ok: true, keys, total: keys.length });
}

/** DELETE /v1/admin/keys/:id */
export async function remove(ctx: Ctx): Promise<Response> {
  requireAdmin(ctx);
  await ctx.env.DB.prepare(`DELETE FROM keys WHERE id = ?1`).bind(ctx.params.id).run();
  return json({ ok: true });
}

/** DELETE /v1/admin/products/:id/keys?status=claimed - clears the stock. */
export async function clearForProduct(ctx: Ctx): Promise<Response> {
  requireAdmin(ctx);
  const status = ctx.url.searchParams.get("status") ?? "";
  // Same reason as list(): an `OR` on a bound param turns this into a full scan.
  const res = status
    ? await ctx.env.DB.prepare(`DELETE FROM keys WHERE product_id = ?1 AND status = ?2`)
        .bind(ctx.params.id, status)
        .run()
    : await ctx.env.DB.prepare(`DELETE FROM keys WHERE product_id = ?1`)
        .bind(ctx.params.id)
        .run();
  return json({ ok: true, deleted: res.meta.changes ?? 0 });
}
