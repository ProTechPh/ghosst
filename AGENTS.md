# AGENTS.md

Flutter Android app (Ghosst): users earn coins from AdMob rewarded ads, then spend
them on license keys or MediaFire-hosted APK/file downloads. The backend is a plain
PHP 8 API on Hostinger (`C:\laragon\www\api\`, deployed to
`https://ghossthub.com/api/v1`) over MySQL. **`SETUP.md` is the real documentation**
(deploy, AdMob SSV, admin, release flow) — `README.md` is untouched Flutter
boilerplate.

## Commands

```powershell
flutter pub get
flutter analyze                 # only lint gate; excludes build/ and android/
flutter test                    # all 78 tests, no network/backend needed
flutter test test/widget_test.dart --plain-name "sign-in rejects a malformed email"
flutter run --flavor play       # --flavor is required: there is no default flavor
flutter run --release --flavor play --dart-define=USE_TEST_ADS=true   # QA ads
flutter build appbundle --release --flavor play --dart-define=USE_TEST_ADS=false
flutter build apk --release --flavor direct
```

Bare `flutter run` / `flutter build apk` fails because both flavors are required.
CI (`.github/workflows/build.yml`) runs `flutter analyze` then `flutter test` and
pins Flutter 3.47.6.

The API is deployed by upload, not by this repo — it lives at
`C:\laragon\www\api\` and is copied to `public_html/api/` on Hostinger. Nothing
backend-related is built or tested from here; run it locally with:

```powershell
php -S 127.0.0.1:8099 -t C:\laragon\www\api C:\laragon\www\api\index.php
```

`api/README.md` covers deploy, env overrides (`GHOSST_DB_*`, `GHOSST_JWT_SECRET`)
and rollback. `JWT_SECRET` and `CLOUDINARY_API_SECRET` live in `api/config.php`.

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
- `cf-ghosst/` was removed. The API is the PHP tree at `C:\laragon\www\api\`:
  `index.php` (router + `ROUTES`), `routes/*` (auth, account, products, keys,
  claims, ads/SSV, uploads, downloads), `lib/*` (http, db, auth, idempotency,
  rewards, cloudinary), `config.php`.
- `C:\laragon\www\database\mobile_app_schema.sql` + `mobile_app_data.sql` — the
  `app_*` MySQL tables and the one-shot D1 → MySQL data copy.
- `docs/*.html` — Play-required privacy policy / account-deletion pages.
  `DELETE /v1/account` deletes claims/rewards/idempotency and **anonymises** the
  user row (email, display name, password hash blanked) so the tombstone id
  survives without the PII. Keep it that way — the page promises real deletion.
- `tool/generate_brand_images.ps1` — regenerates launcher and splash PNGs from
  `assets/images/logo.jpg`.

## Non-obvious constraints

- Ad unit IDs live only in `AdUnits` (`lib/services/ad_service.dart`).
  `USE_TEST_ADS` defaults to `kDebugMode`; release builds use live units unless the
  define is passed. Never ship test-ad builds publicly or live ads in QA artifacts.
- API base URL default in `lib/api/api_config.dart`
  (`https://ghossthub.com/api/v1`); override with
  `--dart-define=API_BASE_URL=...`. The ad-block gate probes this same base as
  its control host, so a wrong URL makes that gate inconclusive, not blocked.
- Both rewarded units must keep their AdMob **server-side verification** URL
  pointed at `/v1/ads/ssv`. If coins never land, check the PHP error log
  (Hostinger File Manager): no request at all means the URL in AdMob is wrong,
  and the code cannot fix that. The handler also rejects foreign ad units and
  paces rewards by a keyed hash of the account email (`api/lib/rewards.php`), so
  deleting and re-registering the same address does not reset the daily cap; a
  logged `SSV blocked:` is that guard, not the URL.
- Coins/stock are mutated only inside the API. A claim runs in a MySQL
  transaction that locks the user row first (`SELECT coins ... FOR UPDATE`), then
  picks the oldest available key, refunding if stock ran out. Lock the user row
  before the key row — reversing that order deadlocks under concurrent claims.
  `POST /v1/claims` requires an `Idempotency-Key` (PK `(user_id, idem_key)`) —
  replaying it returns the stored response. Never write `coins` or `keys` from
  the client.
- Product images are Cloudinary URLs uploaded with an **unsigned** preset, so the
  app never holds a secret. Deleting a product destroys its images server-side
  (`CLOUDINARY_API_SECRET` in `api/config.php`) — nothing cleans up uploads that
  were never attached to a product.
- Bulk key paste is chunked (`KEYS_PER_STATEMENT = 500` in `api/routes/keys.php`)
  to stay under `max_allowed_packet`; dedupe comes from the
  `UNIQUE(product_id, key_value)` index via `INSERT IGNORE`.
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
- Access tokens last 1 h (`ACCESS_TTL` in `api/config.php`) because each refresh
  rotates the session row. Hostinger throttles per account, not per request, so a
  burst of 500s after a deploy usually means a PHP fatal, not quota — read the
  error log before blaming the host.
- Tests mock platform channels (`Security.channel`, `OfficialApk.channel`) and
  inject resolver/prober functions into `AdblockDetector.runCheck`. Widget tests
  depend on exact splash/animation timings — pump explicit durations.
- `.agents/`, `.kilo/` and `skills-lock.json` are gitignored local agent tooling;
  do not treat them as app source.
