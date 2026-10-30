# AGENTS.md

Flutter Android app (Ghosst): users earn coins from AdMob rewarded ads, then spend
them on license keys or MediaFire-hosted APK/file downloads. The backend is a
Cloudflare Worker (`cf-ghosst/`) with D1. **`SETUP.md` is the real documentation**
(deploy, AdMob SSV, admin, release flow) — `README.md` is untouched Flutter
boilerplate.

## Commands

```powershell
flutter pub get
flutter analyze                 # only lint gate; excludes build/ and android/
flutter test                    # all 62 tests, no network/backend needed
flutter test test/widget_test.dart --plain-name "sign-in rejects a malformed email"
flutter run --flavor play       # --flavor is required: there is no default flavor
flutter run --release --flavor play --dart-define=USE_TEST_ADS=true   # QA ads
flutter build appbundle --release --flavor play --dart-define=USE_TEST_ADS=false
flutter build apk --release --flavor direct
```

Bare `flutter run` / `flutter build apk` fails because both flavors are required.
CI (`.github/workflows/build.yml`) runs `flutter analyze` then `flutter test` and
pins Flutter 3.47.6.

The Worker is deployed by hand from `cf-ghosst/`:

```powershell
cd cf-ghosst
npm run typecheck                       # tsc --noEmit
npm test                                # node --test (pure helpers)
npx wrangler d1 execute ghosst --remote --file=migrations/0001_init.sql
npx wrangler deploy
npx wrangler tail ghosst-api            # live logs — the SSV debugger
```

Secrets (`JWT_SECRET`, `CLOUDINARY_API_SECRET`, R2 keys if ever enabled) go
through `wrangler secret put`; never into `wrangler.toml`.

## Layout

- `lib/main.dart` — splash + two launch gates (tamper, ad-block), then `Router`
  and `HomeShell`. No routing package: screens receive callbacks and the tabs are
  an `IndexedStack` in `HomeShell`.
- `lib/services/worker_backend.dart` — the `Backend` static surface every screen
  calls: session, wallet, claims, admin keys, product CRUD. Keep network access
  here, not in screens.
- `lib/api/` — the HTTP layer: `api_client.dart` (Dio + auth/retry
  interceptors), `api_exception.dart` (error → Taglish message), `api_config.dart`
  (base URL, timeouts).
- `lib/services/models.dart` — `Product`/`Claim`/`StockEntry` and friends, shared
  by the screens and the API layer.
- `lib/screens/*` — UI; `lib/premium.dart` shared visual primitives; `lib/theme.dart`
  palette, fonts and motion tokens.
- `cf-ghosst/src/` — the Worker: `index.ts` (router), `routes/*` (auth, account,
  products, keys, claims, ads/SSV, uploads, downloads), `lib/*` (http, cors, auth,
  r2, idempotency, cloudinary).
- `cf-ghosst/migrations/` — D1 schema. `cf-ghosst/test/` — `node --test` units.
- `docs/*.html` — Play-required privacy policy / account-deletion pages.
- `tool/generate_brand_images.ps1` — regenerates launcher and splash PNGs from
  `assets/images/logo.jpg`.

## Non-obvious constraints

- Ad unit IDs live only in `AdUnits` (`lib/services/ad_service.dart`).
  `USE_TEST_ADS` defaults to `kDebugMode`; release builds use live units unless the
  define is passed. Never ship test-ad builds publicly or live ads in QA artifacts.
- API base URL default in `lib/api/api_config.dart`
  (`https://ghosst-api.ghosst.workers.dev/v1`); override with
  `--dart-define=API_BASE_URL=...`.
- Both rewarded units must keep their AdMob **server-side verification** URL
  pointed at `/v1/ads/ssv`. If coins never land, `wrangler tail ghosst-api`: no
  request at all means the URL in AdMob is wrong, and the code cannot fix that.
- Coins/stock are mutated only inside the Worker. A claim deducts with a guarded
  `UPDATE ... WHERE coins >= ? RETURNING` then picks the oldest available key,
  refunding if stock ran out. `POST /v1/claims` requires an `Idempotency-Key`
  (PK `(user_id, key)`) — replaying it returns the stored response. Never write
  `coins` or `keys` from the client.
- Product images are Cloudinary URLs uploaded with an **unsigned** preset, so the
  app never holds a secret. Deleting a product destroys its images server-side
  (`CLOUDINARY_API_SECRET` in the Worker) — nothing cleans up uploads that were
  never attached to a product.
- D1 caps **100 bound parameters** per statement: bulk key paste inserts 20 rows
  per statement, batched 50 statements at a time.
- Two flavors differ at runtime: `play` (no `REQUEST_INSTALL_PACKAGES`, saves APKs
  to Downloads, tamper check skipped) vs `direct` (can launch the installer).
  Flavor is read through the `com.astrixtech.ghosst/build` channel in
  `lib/services/distribution.dart`; unknown builds default to Play behavior.
- Tamper gate (`lib/services/security.dart`) only runs in release on Android.
  `OFFICIAL_SHA256` in `MainActivity.kt` must match the release signing cert —
  update it if the keystore changes. Both tamper and ad-block gates fail open.
- Release builds use the checked-in `android/app/ghosst-release.jks` with R8 on.
  Keep `org.gradle.jvmargs=-Xmx4G` (CI runners OOM otherwise) and
  `kotlin.incremental=false` (C:/D: drive split breaks plugin compilation).
- Every push to `main` auto-bumps `version: x.y.z+N` in `pubspec.yaml`, commits
  `[skip ci]`, and publishes release `vX.Y.Z+N`. Do not bump `N` by hand; bump
  `x.y.z` only when the feature version changes.
- Free plan ceilings: 100k Worker requests/day, 100k D1 rows written/day, 5M rows
  read/day. Access tokens last 1 h (`ACCESS_TTL` in `routes/auth.ts`) because each
  refresh costs two session-row writes. HTTP 1027/1015/1102 arrive as Cloudflare
  HTML, not JSON — `ApiException` maps them to `quotaExceeded`.
- Tests mock platform channels (`Security.channel`, `OfficialApk.channel`) and
  inject resolver/prober functions into `AdblockDetector.runCheck`. Widget tests
  depend on exact splash/animation timings — pump explicit durations.
- `.agents/`, `.kilo/` and `skills-lock.json` are gitignored local agent tooling;
  do not treat them as app source.
