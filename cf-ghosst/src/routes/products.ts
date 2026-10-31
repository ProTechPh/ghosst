import { ApiError, json, readJson } from "../lib/http";
import { requireAdmin } from "../lib/auth";
import { destroyImage } from "../lib/cloudinary";
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
    // Absolute URLs (R2 keys can also be MediaFire links) pass through as-is.
    imageUrls: images.map((key) =>
      /^https?:\/\//i.test(key) ? key : cdn ? `${cdn}/${key}` : key,
    ),
    youtubeUrl: row.youtube_url,
    type: row.type,
    version: row.version,
    fileSize: row.file_size,
    durations,
    availableCount: row.available,
  };
}

// D1 caps a statement at 100 bound parameters: one id per placeholder -> 50.
const IDS_PER_QUERY = 50;

async function attach(env: Env, rows: ProductRow[]) {
  if (rows.length === 0) return [];

  const ids = rows.map((r) => r.id);
  const chunks: string[][] = [];
  for (let i = 0; i < ids.length; i += IDS_PER_QUERY) chunks.push(ids.slice(i, i + IDS_PER_QUERY));

  const [imagePages, durationPages] = await Promise.all([
    Promise.all(
      chunks.map((chunk) =>
        env.DB.prepare(
          `SELECT product_id, object_key FROM product_images
            WHERE product_id IN (${placeholders(chunk)}) ORDER BY position`,
        )
          .bind(...chunk)
          .all<{ product_id: string; object_key: string }>(),
      ),
    ),
    Promise.all(
      chunks.map((chunk) =>
        env.DB.prepare(
          `SELECT product_id, label, cost FROM product_durations
            WHERE product_id IN (${placeholders(chunk)}) ORDER BY cost`,
        )
          .bind(...chunk)
          .all<{ product_id: string; label: string; cost: number }>(),
      ),
    ),
  ]);

  const images = imagePages.flatMap((p) => p.results ?? []);
  const durations = durationPages.flatMap((p) => p.results ?? []);

  return rows.map((row) =>
    toProduct(
      row,
      images.filter((i) => i.product_id === row.id).map((i) => i.object_key),
      durations
        .filter((d) => d.product_id === row.id)
        .map((d) => ({ label: d.label, cost: d.cost })),
      env.PUBLIC_CDN,
    ),
  );
}

function placeholders(chunk: string[]): string {
  return chunk.map((_, i) => `?${i + 1}`).join(",");
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
  const row = await ctx.env.DB.prepare(
    `${SELECT_PRODUCTS} WHERE p.id = ?1${ctx.user?.isAdmin ? "" : " AND p.active = 1"}`,
  )
    .bind(ctx.params.id)
    .first<ProductRow>();
  if (!row) throw new ApiError(404, "product_not_found", "Product not found");

  const [product] = await attach(ctx.env, [row]);

  // The stored download link is admin-only: regular buyers get it from a claim.
  const fileUrl = ctx.user?.isAdmin
    ? ((await ctx.env.DB.prepare(
        `SELECT object_key FROM product_files WHERE product_id = ?1`,
      )
        .bind(row.id)
        .first<{ object_key: string }>())?.object_key ?? "")
    : "";

  return json({ ok: true, product: { ...product, fileUrl } });
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
  fileUrl?: string;
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

  const before = body.imageKeys
    ? ((await ctx.env.DB.prepare(
        `SELECT object_key FROM product_images WHERE product_id = ?1`,
      )
        .bind(id)
        .all<{ object_key: string }>()).results ?? [])
    : [];

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

  if (body.imageKeys) {
    const kept = new Set(body.imageKeys);
    await discardImages(
      ctx.env,
      before.map((i) => i.object_key).filter((k) => !kept.has(k)),
    );
  }

  // The stored download link travels with the product for the admin form.
  if (body.fileUrl !== undefined) {
    const link = body.fileUrl.trim();
    if (link) {
      const filename = link.split("/").pop()?.split("?")[0] ?? "";
      await ctx.env.DB.prepare(
        `INSERT INTO product_files (product_id, object_key, filename, updated_at)
         VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(product_id) DO UPDATE SET
           object_key = excluded.object_key,
           sha256 = NULL, -- a new link invalidates the old file's hash
           updated_at = excluded.updated_at`,
      )
        .bind(id, link, filename || "download", new Date().toISOString())
        .run();
    } else {
      await ctx.env.DB.prepare(`DELETE FROM product_files WHERE product_id = ?1`)
        .bind(id)
        .run();
    }
  }

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
  const cleaned = await discardImages(ctx.env, keys);

  return json({ ok: true, filesDeleted: cleaned });
}

/**
 * Best effort: a dangling object costs storage, not correctness. Absolute URLs are
 * Cloudinary/MediaFire; `destroyImage` ignores everything that is not our cloud.
 */
async function discardImages(env: Env, keys: string[]): Promise<number> {
  const results = await Promise.allSettled(
    keys.map((key) => (/^https?:\/\//i.test(key) ? destroyImage(env, key) : env.BUCKET?.delete(key))),
  );
  return results.filter((r) => r.status === "fulfilled" && r.value === true).length;
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
