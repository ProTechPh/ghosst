# ghossthub.com-only API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `https://ghossthub.com/api/v1` the only API host in new builds and remove the `mail.ghossthub.com` DNS record immediately, with the owner accepting the old-version compatibility risk.

**Architecture:** Collapse `ApiClient` back to one API Dio plus the existing bare refresh Dio. Keep the IPv4-first TLS adapter, auth/retry interceptors, timeouts, and error mapping. `ApiConfig.publicUrl()` continues deriving relative media URLs from the single base URL.

**Tech Stack:** Flutter/Dart, Dio, `dart:io`, Flutter tests, Cloudflare DNS.

**Spec:** `docs/superpowers/specs/2026-11-28-api-main-only-design.md`

## Global Constraints

- Do not run `flutter run`; verify with `flutter analyze`, `flutter test`, and `flutter build`.
- CI pins Flutter 3.47.6; do not change Gradle/AGP just to satisfy the local newer Flutter SDK.
- Keep network access in `lib/api/`; do not add endpoint logic to screens.
- Keep normal TLS certificate validation and SNI.
- Do not manually bump the `+N` build number.
- The owner explicitly accepts that deleting `mail.ghossthub.com` immediately can break older app versions without a working fallback.

## Review Focus

- **IPv6-only network:** API still connects when DNS returns no IPv4 address; pinned by `ApiClient.preferredApiAddress` tests.
- **Cloudflare HTTPS:** SNI and certificate validation remain correct after removing the second host; pinned by the live Dio adapter smoke check.
- **Cloudflare 403/WAF:** no origin fallback remains by design; verify the explicit app User-Agent and monitor after rollout.
- **Relative media URLs:** product/cover keys resolve under `ghossthub.com`; pinned by `ApiConfig.publicUrl` test.
- **Old installed apps:** versions pinned to `mail.ghossthub.com` may fail after DNS deletion; owner-accepted production risk, documented in the spec.

---

### Task 1: Checkpoint the completed IPv4-first API fix

**Files:**
- Modify: `lib/api/api_client.dart`
- Create: `test/api_client_test.dart`

**Interfaces:**
- Produces: `ApiClient.preferredApiAddress(String host, {Future<List<InternetAddress>> Function(String)? resolve}) -> Future<InternetAddress>`.

- [x] Confirm `flutter test test/api_client_test.dart` passes.
- [x] Confirm `flutter analyze lib/api/api_client.dart test/api_client_test.dart` reports no issues.
- [x] Commit the isolated IPv4-first change.

```bash
git add lib/api/api_client.dart test/api_client_test.dart
git commit -m "fix: prefer IPv4 for API connections"
```

### Task 2: Pin the single-host configuration with a failing test

**Files:**
- Create: `test/api_config_test.dart`
- Test: `test/api_config_test.dart`

**Interfaces:**
- Consumes: `ApiConfig.baseUrl`, `ApiConfig.publicUrl(String key)`.

- [x] Write a test asserting the default base URL is `https://ghossthub.com/api/v1`.
- [x] Write a test asserting `publicUrl('uploads/products/example.jpg')` returns `https://ghossthub.com/uploads/products/example.jpg`.
- [x] Run `flutter test test/api_config_test.dart` and verify it fails because the current default is still `mail.ghossthub.com`.

### Task 3: Make `ApiConfig` single-host

**Files:**
- Modify: `lib/api/api_config.dart`
- Test: `test/api_config_test.dart`

**Interfaces:**
- Produces: `static const String baseUrl` defaulting to `https://ghossthub.com/api/v1`.
- Produces: `static String publicUrl(String key)` using `baseUrl`.
- Removes: `fallbackBaseUrl` and `baseUrls`.

- [x] Change the default `baseUrl` to `https://ghossthub.com/api/v1`.
- [x] Remove `fallbackBaseUrl`, `API_FALLBACK_URL`, and `baseUrls`.
- [x] Replace the origin/fallback comments with a single-host comment.
- [x] Run `flutter test test/api_config_test.dart` and verify it passes.

### Task 4: Collapse `ApiClient` to one API host

**Files:**
- Modify: `lib/api/api_client.dart`
- Test: `test/api_client_test.dart`

**Interfaces:**
- Consumes: `ApiConfig.baseUrl`.
- Produces: one `_primary` Dio and one `_refreshDio`, both using `_apiHttpClient()`.
- Removes: `_fallback`, `_run` host retry, `_isTransportFailure`, and fallback interceptor setup.

- [x] Remove the two-host class documentation and fallback fields/setup.
- [x] Keep `_primary` construction, injected-Dio behavior, auth/retry interceptors, and debug logging.
- [x] Simplify `_run` to execute only against `_primary` and map `DioException` through `ApiException.fromDio`.
- [x] Keep `_refreshDio` pointed at `ApiConfig.baseUrl` with the IPv4-first adapter.
- [x] Run `flutter test test/api_client_test.dart test/api_config_test.dart` and verify both pass.
- [x] Run `flutter analyze lib/api/api_client.dart lib/api/api_config.dart test/api_client_test.dart test/api_config_test.dart` and verify no issues.

### Task 5: Update host documentation

**Files:**
- Modify: `SETUP.md`
- Modify: `docs/superpowers/specs/2026-11-28-api-main-only-design.md`
- Create: `docs/superpowers/plans/2026-11-28-api-main-only.md`

**Interfaces:**
- None.

- [x] Replace the push-host wording so `ghossthub.com` is the sole app API/push host.
- [x] Remove any remaining statement that `mail.ghossthub.com` is the app base URL.
- [x] Keep the explicit old-version DNS-deletion risk in the design doc.
- [x] Run `git diff --check`.

### Task 6: Full verification and release build

**Files:**
- All tracked app/test/docs changes.

**Interfaces:**
- Consumes: completed Tasks 1–5.
- Produces: verified direct release APK ready for distribution.

- [x] Run `flutter test` and verify all tests pass.
- [x] Run `flutter analyze lib/api/api_client.dart lib/api/api_config.dart test/api_client_test.dart test/api_config_test.dart` and verify no issues.
- [x] Run the standalone Dio IPv4-first live smoke against `https://ghossthub.com/api/v1/products` and verify 200 with `ok: true`.
- [x] Run `flutter build apk --release --flavor direct --android-skip-build-dependency-validation` and verify exit 0.
- [x] Review `git status --short` and `git diff --check`.
- [x] Commit the main-only app/config/docs change.

```bash
git add lib/api/api_client.dart lib/api/api_config.dart test/api_client_test.dart test/api_config_test.dart SETUP.md docs/superpowers/specs/2026-11-28-api-main-only-design.md docs/superpowers/plans/2026-11-28-api-main-only.md
git commit -m "fix: use ghossthub.com as the only API host"
```

### Task 7: Delete the mail DNS record and verify production DNS/API

**Files:**
- Production: Cloudflare DNS for `ghossthub.com`.

**Interfaces:**
- Consumes: verified Task 6 release candidate and Cloudflare dashboard access.
- Produces: no `mail.ghossthub.com` DNS record; `ghossthub.com` remains proxied and healthy.

- [ ] Delete only the `mail.ghossthub.com` A record pointing to `18.136.157.239`.
- [ ] Do not change the `ghossthub.com` proxy, SSL/TLS mode, or certificate.
- [ ] Verify public resolvers return NXDOMAIN for `mail.ghossthub.com`.
- [ ] Verify `ghossthub.com` still resolves to Cloudflare and `GET https://ghossthub.com/api/v1/products` returns 200 JSON.

### Task 8: Distribute and monitor

**Files:**
- Production: app distribution, PHP device log, Cloudflare security analytics.

**Interfaces:**
- Consumes: Tasks 6–7.

- [ ] Distribute the verified main-only APK.
- [ ] Check PHP device logs for successful `host=ghossthub.com` requests from the new app.
- [ ] Check Cloudflare security analytics for new `/api/v1/` 403s or mitigations.
- [ ] Report any regression immediately; there is no origin-host fallback by design.
