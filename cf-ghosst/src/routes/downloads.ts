import { ApiError, json } from "../lib/http";
import { fileTicket } from "../lib/r2";
import type { Ctx } from "../index";

/**
 * GET /v1/downloads/:productId
 * The only outlet for a paid file. No claim row ⇒ no URL, ever — which is
 * exactly the hole MediaFire left open.
 */
export async function ticket(ctx: Ctx): Promise<Response> {
  const productId = ctx.params.id;
  const uid = ctx.user!.id;

  const claim = await ctx.env.DB.prepare(
    `SELECT product_name, created_at FROM claims
      WHERE user_id = ?1 AND product_id = ?2 AND object_key IS NOT NULL
      ORDER BY created_at DESC LIMIT 1`,
  )
    .bind(uid, productId)
    .first<{ product_name: string; created_at: string }>();

  if (!claim) throw new ApiError(403, "not_owned", "Buy this item first");

  const file = await ctx.env.DB.prepare(
    `SELECT object_key, filename, size FROM product_files WHERE product_id = ?1`,
  )
    .bind(productId)
    .first<{ object_key: string; filename: string; size: number }>();

  if (!file) throw new ApiError(404, "download_unavailable", "Download not configured");

  const t = await fileTicket(ctx.env, file.object_key, file.filename, 300);

  return json({
    ok: true,
    url: t.url,
    filename: file.filename,
    size: file.size,
    expiresIn: t.expiresIn,
    expiresAt: new Date(Date.now() + t.expiresIn * 1000).toISOString(),
  });
}
