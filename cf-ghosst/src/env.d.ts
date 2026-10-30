interface Env {
  DB: D1Database;
  JWT_SECRET: string;
  PUBLIC_CDN: string;
  ALLOWED_ORIGINS?: string;
  COINS_PER_REWARD?: string;
  // R2 is optional: without these the upload/download routes answer 503 and
  // `product_files.object_key` is expected to hold a full MediaFire link.
  BUCKET?: R2Bucket;
  R2_ACCOUNT_ID?: string;
  R2_BUCKET?: string;
  R2_ACCESS_KEY_ID?: string;
  R2_SECRET_ACCESS_KEY?: string;
  // Cloudinary: the app uploads with an unsigned preset; only the Worker holds
  // the secret needed to delete an asset.
  CLOUDINARY_CLOUD_NAME?: string;
  CLOUDINARY_API_KEY?: string;
  CLOUDINARY_API_SECRET?: string;
}
