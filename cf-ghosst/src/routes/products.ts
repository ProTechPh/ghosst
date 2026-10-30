import { ApiError, json, readJson } from "../lib/http";
import { requireAdmin } from "../lib/auth";
import type { Ctx } from "../index";

interface ProductRow {
  id: string;
  name: string;
  cost: number;
  active: number;
  description: string;
  youtube_url: string;
  type: string;
  version: string;
  file_size: string;
  available: number;
}

const SELECT_PRODUCTS = `
  SELECT p.id, p.name, p.cost, p.active, p.description, p.youtube_url, p.type,
         p.version, p.file_size,
         (SELECT COUNT(*) FROM keys k WHERE k.product_id = p.id AND k.status = 'available') AS available
    FROM products p`;

function toProduct(
  row: ProductRow,
  images: string[],
  durations: Array<{ label: string; cost: number }>,
  cdn: string,
) {
  return {
    id: row.id,
    name: row.name,
    cost: row.cost,
    active: row.active === 1,
    description: row.description,
    imageUrls: images.map((key) => `${cdn}/${key}`),
    youtubeUrl: row.youtube_url,
    type: row.type,
    version: row.version,
    fileSize: row.file_size,
    durations,
    availableCount: row.available,
  };
}

async function attach(env: Env, rows: ProductRow[]) {
  if (rows.length === 0) return [];

  const ids = rows.map((r) => r.id);
  const placeholders = ids.map((_, i) => `?${i + 1}`).join(",");

  const [images, durations] = await Promise.all([
    env.DB.prepare(
      `SELECT product_id, object_key FROM product_images
        WHERE product_id IN (${placeholders}) ORDER BY position`,
    )
      .bind(...ids)
      .all<{ product_id: string; object_key: string }>(),
    env.DB.prepare(
      `SELECT product_id, label, cost FROM product_durations
        WHERE product_id IN (${placeholders}) ORDER BY cost`,
    )
      .bind(...ids)
      .all<{ product_id: string; label: string; cost: number }>(),
  ]);

  return rows.map((row) =>
    toProduct(
      row,
      (images.results ?? []).filter((i) => i.product_id === row.id).map((i) => i.object_key),
      (durations.results ?? [])
        .filter((d) => d.product_id === row.id)
        .map((d) => ({ label: d.label, cost: d.cost })),
      env.PUBLIC_CDN,
    ),
  );
}

export async function list(ctx: Ctx): Promise<Response> {
  const includeInactive = ctx.url.searchParams.get("all") === "1" && ctx.user?.isAdmin;
  const rows = await ctx.env.DB.prepare(
    `${SELECT_PRODUCTS} ${includeInactive ? "" : "WHERE p.active = 1"} ORDER BY p.name`,
  ).all<ProductRow>();

  const products = await attach(ctx.env, rows.results ?? []);
  return json(
    { ok: true, products },
    200,
  );
}

export async function get(ctx: Ctx): Promise<Response> {
  const row = await ctx.env.DB.prepare(`${SELECT_PRODUCTS} WHERE p.id = ?1`)
    .bind(ctx.params.id)
    .first<ProductRow>();
  if (!row) throw new ApiError(404, "product_not_found", "Product not found");

  const [product] = await attach(ctx.env, [row]);
  return json({ ok: true, product });
}

interface ProductBody {
  name?: string;
  cost?: number;
  description?: string;
  youtubeUrl?: string;
  type?: string;
  version?: string;
  fileSize?: string;
  active?: boolean;
  imageKeys?: string[];
  durations?: Array<{ label: string; cost: number }>;
}

export async function create(ctx: Ctx): Promise<Response> {
  requireAdmin(ctx);
  const body = await readJson<ProductBody>(ctx.req);
  const name = (body.name ?? "").trim();
  if (!name) throw new ApiError(400, "invalid_product", "Name is required");

  const type = body.type ?? "key";
  if (!["key", "apk", "file"].includes(type)) {
    throw new ApiError(400, "invalid_product", "type must be key, apk or file");
  }

  const id = crypto.randomUUID();
  const now = new Date().toISOString();

  await ctx.env.DB.prepare(
    `INSERT INTO products (id, name, cost, active, description, youtube_url, type, version, file_size, created_at, updated_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?10)`,
  )
    .bind(
      id,
      name,
      Math.max(0, Math.floor(body.cost ?? 50)),
      body.active === false ? 0 : 1,
      body.description ?? "",
      body.youtubeUrl ?? "",
      type,
      body.version ?? "",
      body.fileSize ?? "",
      now,
    )
    .run();

  await applyRelations(ctx.env, id, body);
  return get({ ...ctx, params: { ...ctx.params, id } });
}

export async function update(ctx: Ctx): Promise<Response> {
  requireAdmin(ctx);
  const body = await readJson<ProductBody>(ctx.req);
  const id = ctx.params.id;

  const existing = await ctx.env.DB.prepare(`SELECT id FROM products WHERE id = ?1`)
    .bind(id)
    .first<{ id: string }>();
  if (!existing) throw new ApiError(404, "product_not_found", "Product not found");

  await ctx.env.DB.prepare(
    `UPDATE products SET
       name = COALESCE(?2, name),
       cost = COALESCE(?3, cost),
       description = COALESCE(?4, description),
       youtube_url = COALESCE(?5, youtube_url),
       type = COALESCE(?6, type),
       version = COALESCE(?7, version),
       file_size = COALESCE(?8, file_size),
       active = COALESCE(?9, active),
       updated_at = ?10
     WHERE id = ?1`,
  )
    .bind(
      id,
      body.name ?? null,
      body.cost == null ? null : Math.max(0, Math.floor(body.cost)),
      body.description ?? null,
      body.youtubeUrl ?? null,
      body.type ?? null,
      body.version ?? null,
      body.fileSize ?? null,
      body.active == null ? null : body.active ? 1 : 0,
      new Date().toISOString(),
    )
    .run();

  await applyRelations(ctx.env, id, body);
  return get(ctx);
}

export async function remove(ctx: Ctx): Promise<Response> {
  requireAdmin(ctx);
  const id = ctx.params.id;

  const images = await ctx.env.DB.prepare(
    `SELECT object_key FROM product_images WHERE product_id = ?1`,
  )
    .bind(id)
    .all<{ object_key: string }>();

  const files = await ctx.env.DB.prepare(
    `SELECT object_key FROM product_files WHERE product_id = ?1`,
  )
    .bind(id)
    .first<{ object_key: string }>();

  await ctx.env.DB.prepare(`DELETE FROM products WHERE id = ?1`).bind(id).run();

  // Best effort: a dangling object costs storage, not correctness.
  const keys = [
    ...(images.results ?? []).map((i) => i.object_key),
    ...(files?.object_key ? [files.object_key] : []),
  ];
  await Promise.allSettled(keys.map((key) => ctx.env.BUCKET.delete(key)));

  return json({ ok: true });
}

/** Replaces images/durations wholesale — the admin UI always sends full lists. */
async function applyRelations(env: Env, productId: string, body: ProductBody) {
  if (body.imageKeys) {
    await env.DB.prepare(`DELETE FROM product_images WHERE product_id = ?1`)
      .bind(productId)
      .run();
    const now = new Date().toISOString();
    for (const [position, key] of body.imageKeys.entries()) {
      await env.DB.prepare(
        `INSERT INTO product_images (id, product_id, object_key, position, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5)`,
      )
        .bind(crypto.randomUUID(), productId, key, position, now)
        .run();
    }
  }

  if (body.durations) {
    await env.DB.prepare(`DELETE FROM product_durations WHERE product_id = ?1`)
      .bind(productId)
      .run();
    for (const d of body.durations) {
      if (!d.label) continue;
      await env.DB.prepare(
        `INSERT INTO product_durations (product_id, label, cost) VALUES (?1, ?2, ?3)
         ON CONFLICT(product_id, label) DO UPDATE SET cost = excluded.cost`,
      )
        .bind(productId, d.label, Math.max(0, Math.floor(d.cost ?? 0)))
        .run();
    }
  }
}
