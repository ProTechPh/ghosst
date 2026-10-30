import { ApiError, json, readJson } from "../lib/http";
import { requireAdmin } from "../lib/auth";
import { presignPut, storageReady, verifyObject } from "../lib/r2";
import type { Ctx } from "../index";

const IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);
const FILE_TYPES = new Set([
  "application/vnd.android.package-archive",
  "application/zip",
  "application/pdf",
  "application/octet-stream",
]);

const LIMITS = {
  "product-image": { max: 5 * 1024 * 1024, types: IMAGE_TYPES, ext: /\.(jpe?g|png|webp|gif)$/i },
  "product-file": { max: 300 * 1024 * 1024, types: FILE_TYPES, ext: /\.(apk|zip|pdf|bin)$/i },
} as const;

type Scope = keyof typeof LIMITS;

interface PresignBody {
  scope?: Scope;
  filename?: string;
  contentType?: string;
  size?: number;
  productId?: string;
}

/** POST /v1/uploads/presign → { objectKey, uploadUrl, headers, expiresIn } */
export async function presign(ctx: Ctx): Promise<Response> {
  requireAdmin(ctx);
  const body = await readJson<PresignBody>(ctx.req);
  const scope = body.scope;
  if (!scope || !(scope in LIMITS)) throw new ApiError(400, "bad_scope", "Unknown upload scope");

  const rule = LIMITS[scope];
  const contentType = body.contentType ?? "";
  const filename = body.filename ?? "";
  const size = Number(body.size ?? 0);

  if (!rule.types.has(contentType)) {
    throw new ApiError(415, "bad_type", `Content type ${contentType || "(none)"} is not allowed`);
  }
  if (!rule.ext.test(filename)) {
    throw new ApiError(415, "bad_extension", "File extension does not match the allowed list");
  }
  if (!Number.isFinite(size) || size <= 0 || size > rule.max) {
    throw new ApiError(413, "too_large", `Max ${Math.round(rule.max / 1048576)} MB`);
  }

  // Never trust the client filename: keep the extension, drop everything else.
  const ext = rule.ext.exec(filename)![0].toLowerCase();
  const objectKey = `${scope}s/${body.productId || "orphan"}/${crypto.randomUUID()}${ext}`;

  if (!storageReady(ctx.env)) {
    throw new ApiError(503, "storage_not_configured", "Uploads are off — R2 is not set up yet");
  }

  const ticket = await presignPut(ctx.env, objectKey, contentType, 300);
  return json({
    ok: true,
    objectKey,
    uploadUrl: ticket.url,
    headers: ticket.headers,
    expiresIn: ticket.expiresIn,
    maxSize: rule.max,
  });
}

interface CompleteBody {
  objectKey?: string;
  productId?: string;
  kind?: "image" | "file";
  filename?: string;
  expectedSize?: number;
  expectedType?: string;
}

/** POST /v1/uploads/complete — verifies R2 metadata, then persists the row. */
export async function complete(ctx: Ctx): Promise<Response> {
  requireAdmin(ctx);
  const body = await readJson<CompleteBody>(ctx.req);
  const objectKey = body.objectKey ?? "";
  const productId = body.productId ?? "";
  const kind = body.kind === "file" ? "file" : "image";

  if (!objectKey.startsWith("product-")) throw new ApiError(400, "bad_key", "Object key rejected");
  if (!productId) throw new ApiError(400, "invalid_product", "productId is required");

  const meta = await verifyObject(ctx.env, objectKey);
  if (!meta) throw new ApiError(409, "upload_missing", "Upload did not reach storage — retry");

  if (meta.size !== Number(body.expectedSize ?? -1)) {
    await ctx.env.BUCKET?.delete(objectKey);
    throw new ApiError(409, "size_mismatch", "Uploaded size did not match — retry");
  }
  if (meta.contentType !== (body.expectedType ?? "")) {
    await ctx.env.BUCKET?.delete(objectKey);
    throw new ApiError(415, "type_mismatch", "Uploaded content type did not match");
  }

  const now = new Date().toISOString();
  if (kind === "image") {
    await ctx.env.DB.prepare(
      `INSERT INTO product_images (id, product_id, object_key, position, created_at)
       VALUES (?1, ?2, ?3,
         COALESCE((SELECT MAX(position) + 1 FROM product_images WHERE product_id = ?2), 0), ?4)`,
    )
      .bind(crypto.randomUUID(), productId, objectKey, now)
      .run();
  } else {
    await ctx.env.DB.prepare(
      `INSERT INTO product_files (product_id, object_key, filename, size, content_type, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6)
       ON CONFLICT(product_id) DO UPDATE SET
         object_key = excluded.object_key, filename = excluded.filename,
         size = excluded.size, content_type = excluded.content_type,
         updated_at = excluded.updated_at`,
    )
      .bind(productId, objectKey, body.filename ?? objectKey.split("/").pop()!, meta.size, meta.contentType, now)
      .run();
  }

  return json({
    ok: true,
    objectKey,
    publicUrl: kind === "image" ? `${ctx.env.PUBLIC_CDN}/${objectKey}` : null,
    size: meta.size,
  });
}
