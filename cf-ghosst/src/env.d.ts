interface Env {
  DB: D1Database;
  BUCKET: R2Bucket;
  JWT_SECRET: string;
  R2_ACCOUNT_ID: string;
  R2_BUCKET: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  PUBLIC_CDN: string;
  ALLOWED_ORIGINS?: string;
  COINS_PER_REWARD?: string;
}
