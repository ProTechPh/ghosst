# AGENTS.md

Flutter Android app (Ghosst): users earn coins from AdMob rewarded ads, then spend
them on license keys or MediaFire-hosted APK/file downloads. Appwrite is the
backend. **`SETUP.md` is the real documentation** (schema, function deploy, AdMob,
release flow) — `README.md` is untouched Flutter boilerplate.

## Commands

```powershell
flutter pub get
flutter analyze                 # only lint gate; excludes build/ and android/
flutter test                    # all 53 tests, no network/backend needed
flutter test test/widget_test.dart --plain-name "sign-in rejects a malformed email"
flutter run --flavor play       # --flavor is required: there is no default flavor
flutter run --release --flavor play --dart-define=USE_TEST_ADS=true   # QA ads
flutter build appbundle --release --flavor play --dart-define=USE_TEST_ADS=false
flutter build apk --release --flavor direct
```

Bare `flutter run` / `flutter build apk` fails because both flavors are required.
CI (`.github/workflows/build.yml`) runs `flutter analyze` then `flutter test` and
pins Flutter 3.47.6.

Backend changes are deployed by hand:

```powershell
tar -czf claim.tar.gz -C functions/claim .
```

Then upload that archive as the `claim` function deployment. `functions/reward-ssv/`
is reference-only — do not deploy it. `claim.tar.gz` at the repo root is a stale
build artifact, not source.

## Layout

- `lib/main.dart` — splash + two launch gates (tamper, ad-block), then `Router`
  and `HomeShell`. No routing package: screens receive callbacks and the tabs are
  an `IndexedStack` in `HomeShell`.
- `lib/services/backend.dart` — every Appwrite collection/function call (static
  methods; ids in `Col`/`Fn`). Keep DB access here, not in screens.
- `lib/screens/*` — UI; `lib/premium.dart` shared visual primitives; `lib/theme.dart`
  palette, fonts and motion tokens.
- `functions/claim/index.js` — the only deployed function: claims, AdMob SSV,
  account deletion, YouTube embed. Dependency-free Node (REST calls only).
- `docs/*.html` — Play-required privacy policy / account-deletion pages.
- `tool/generate_brand_images.ps1` — regenerates launcher and splash PNGs from
  `assets/images/logo.jpg`.

## Non-obvious constraints

- `dependency_overrides` in `pubspec.yaml` are load-bearing: appwrite 12.x pins a
  `flutter_web_auth_2` that no longer compiles, and `file_picker` needs `web` 1.x.
  Do not "clean them up" without rebuilding.
- Ad unit IDs live only in `AdUnits` (`lib/services/ad_service.dart`).
  `USE_TEST_ADS` defaults to `kDebugMode`; release builds use live units unless the
  define is passed. Never ship test-ad builds publicly or live ads in QA artifacts.
- Appwrite endpoint/project default in `lib/appwrite_client.dart`
  (`sgp.cloud.appwrite.io`, project `6ac4baef0010879da982`); override with
  `--dart-define=APPWRITE_ENDPOINT=... --dart-define=APPWRITE_PROJECT_ID=...`.
- The Appwrite schema is manual (SETUP.md §2). Writes tolerate missing optional
  columns, but `claim` reads `products.type`, `keys.duration`, `claims.downloadUrl`,
  and needs the `product_status` index.
- Coins/stock are mutated only server-side inside `claim`, behind the `crit` lock
  document in `ad_rewards` (30s stale takeover). Never write `coins` or `keys` from
  the client. `keys` and `app_files` are admin-only reads; users get download URLs
  only through `claim`.
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
- Tests mock platform channels (`Security.channel`, `OfficialApk.channel`) and
  inject resolver/prober functions into `AdblockDetector.runCheck`. Widget tests
  depend on exact splash/animation timings — pump explicit durations.
- `.agents/` and `skills-lock.json` are gitignored local agent tooling; do not treat
  them as app source.
