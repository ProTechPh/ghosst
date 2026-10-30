# cf-ghosst

Cloudflare Workers API for Ghosst: Workers + D1 + R2, replacing Appwrite.
The Flutter client lives in `../lib/api/` and `../lib/services/api_backend.dart`.

## Routes

| Method | Path | Auth |
|---|---|---|
| POST | `/v1/auth/register` · `/login` · `/refresh` | none |
| POST | `/v1/auth/logout` | user |
| GET | `/v1/me` · `/v1/wallet` | user |
| DELETE | `/v1/account` (`{"confirm":"DELETE"}`) | user |
| GET | `/v1/products` · `/v1/products/:id` | optional (`?all=1` = admin) |
| POST/PATCH/DELETE | `/v1/products` | admin |
| POST/GET | `/v1/admin/keys` | admin |
| DELETE | `/v1/admin/keys/:id` · `/v1/admin/products/:id/keys` | admin |
| POST/GET | `/v1/claims` (`Idempotency-Key` required on POST) | user |
| POST | `/v1/uploads/presign` · `/v1/uploads/complete` | admin |
| GET | `/v1/downloads/:productId` | owner only |
| GET | `/v1/ads/ssv` | Google (ECDSA signature) |

Errors are always `{ ok: false, error: { code, message, requestId } }`.

## Deploy

```powershell
npx wrangler d1 create ghosst          # put the id in wrangler.toml
npx wrangler r2 bucket create ghosst-media
npx wrangler r2 bucket cors put ghosst-media --cors r2-cors.json
npx wrangler secret put JWT_SECRET     # openssl rand -base64 48
npx wrangler secret put R2_ACCESS_KEY_ID
npx wrangler secret put R2_SECRET_ACCESS_KEY
npx wrangler d1 execute ghosst --remote --file=migrations/0001_init.sql
npx wrangler deploy
```

Also set `R2_ACCOUNT_ID`, `R2_BUCKET`, `PUBLIC_CDN`, `ALLOWED_ORIGINS` in `wrangler.toml`,
and point AdMob's SSV callback at `https://api.ghosst.app/v1/ads/ssv` (bare URL, no query).

## Local

```powershell
npm install
npm run db:local
npm run dev            # http://127.0.0.1:8787
flutter run --release --flavor play --dart-define=API_BASE_URL=http://127.0.0.1:8787/v1
```

`.dev.vars` holds local secrets (gitignored).

## Notes

- Claim order is charge → pick key → refund if out of stock. The guarded
  `UPDATE ... WHERE coins >= ?` is the only serialization point; there is no
  lock document any more.
- `POST /v1/claims` is replayed from the `idempotency` table, so a dropped
  connection never charges twice.
- R2 stays private. Paid files leave only through `GET /v1/downloads/:id`,
  which checks the purchase first and returns a 5-minute presigned URL.
- D1 caps 100 bound parameters per statement — `routes/keys.ts` batches 20 rows.
