# Unity Ads Direct Fallback — Design

Date: 2026-11-10
Status: proposed

## Intent

When AdMob has no fill or fails to show the rewarded ad, show a rewarded ad
directly from Unity Ads so the Earn tab still works while the AdMob account is
under assessment. Coins must still be credited only after a verified reward.

## Goals

- Direct Unity rewarded fallback only when AdMob did **not** show an ad.
- Never credit coins from a client-only callback; use Unity server-to-server
  (S2S) verification.
- Feature-flagged until Unity S2S is enabled and the secret is on the server.
- Reuse the existing daily cap, idempotency, and wallet logic.
- No change to the AdMob path when AdMob fills.

## Non-goals

- Replacing AdMob mediation; this is a fallback, not a second primary.
- Direct Unity banner or interstitial; rewarded only.
- Client-side coin credit.
- Fixing the AdMob account assessment.

## Constraints

- Unity SDK is already bundled by `gma_mediation_unity` 1.11.1 (adapter
  4.20.1.0). For direct Kotlin calls, add
  `com.unity3d.ads:unity-ads:4.20.1` to the app module: the mediation plugin's
  `implementation` dependency is not on the app's compile classpath.
- Unity S2S is not enabled by default. Unity Ads Support must enable it and
  provide the HMAC-MD5 secret.
- Direct Unity and AdMob mediation share the Unity SDK singleton. Use the same
  Game ID, check `UnityAds.isInitialized()`, and use a **separate placement** so
  the two paths never load the same placement at once.
- The AdMob SSV path stays unchanged.
- `app_ad_rewards` is the ledger; `reward_verdict` is the shared daily cap/gap.

## Approaches

A. Wait for the assessment to lift. No code; no Unity fill now.
B. Add another network's AdMob waterfall (AppLovin/Liftoff/Pangle). Waterfall is
   exempt from the account limit; same SSV path; no new reward endpoint.
C. Direct Unity SDK + Unity S2S. **Chosen.**

## Design (C)

### App

- `android/app/build.gradle.kts`: add
  `implementation("com.unity3d.ads:unity-ads:4.20.1")` for the platform bridge.
- `MainActivity.kt`: new `MethodChannel("com.astrixtech.ghosst/unityads")`:
  - `initialize(gameId, testMode)` — skip if `UnityAds.isInitialized()`.
  - `load(placementId)` — `UnityAds.load` with a load listener.
  - `show(placementId, userId)` — set
    `PlayerMetaData(this).setServerId(userId).commit()` before `UnityAds.show`.
  - Native events back to Dart: `loaded`, `loadFailed`, `shown`, `completed`,
    `skipped`, `failed`, `closed`.
- `lib/services/unity_direct_ads.dart`: Dart wrapper + state machine.
  `enabled` comes from `bool.fromEnvironment('UNITY_DIRECT_ENABLED')`.
  Game ID `800392172`; placement `BP_Rewarded_Direct` (overridable through
  `--dart-define`).
- `lib/screens/earn_screen.dart`: when AdMob reports no-fill/network failure and
  the flag is on, call `_watchUnityAd()`. `completed` → existing `_verify()`
  wallet poll. `closed` without completion → short cooldown.
- `lib/services/ad_service.dart`: expose a small outcome from `show()` (or add
  `showRewardedOrFallback`) so `EarnScreen` can tell "AdMob showed" from
  "AdMob unavailable". The smallest change wins.

### Backend

- `api/config.php`: `UNITY_S2S_SECRET` (empty default; env
  `GHOSST_UNITY_S2S_SECRET`). Empty = endpoint returns 503.
- `api/index.php`: `GET /v1/ads/unity-s2s` → `ads_unity_s2s` (no JWT).
- `api/routes/ads.php`:
  - Verify `sid`, `oid`, `hmac`. Parameter string = all query params except
    `hmac`, alphabetical key=value, comma-joined.
    `hash_hmac('md5', $paramString, UNITY_S2S_SECRET)` must match.
  - `sid` = backend user UUID; `oid` = Unity offer id.
  - Dedupe by `id = 'u_' . $oid` in `app_ad_rewards`.
  - Apply `reward_verdict` (shared daily cap/gap), then
    `UPDATE app_users SET coins = coins + COINS_PER_REWARD`.
  - Return `200` + `1` on success and on duplicate/cap (no retry); `4xx/5xx`
    on bad HMAC or DB failure. Log invalid HMACs with `log_line`.
  - Extract the shared credit block from `ads_ssv` into a helper if the diff
    stays small; otherwise mirror it with a comment.
- Unity Support callback URL:
  `https://ghossthub.com/api/v1/ads/unity-s2s`.

### Flag and rollout

- `UNITY_DIRECT_ENABLED` default **false**.
- Enable only after Unity Support confirms S2S and the secret is set.
- QA build:
  `flutter run --release --flavor play --dart-define=USE_TEST_ADS=false --dart-define=ADMOB_TEST_DEVICE_IDS=<device-id> --dart-define=UNITY_DIRECT_ENABLED=true`
  with Unity test mode on.
- If Unity S2S cannot be enabled, do not ship the fallback; use approach B.

## External steps

1. Unity dashboard: create a direct rewarded placement (`BP_Rewarded_Direct`)
   and note the id.
2. Unity Ads Support: enable S2S for Game ID `800392172` with the callback URL
   above; receive the secret.
3. Set `UNITY_S2S_SECRET` on the server (not in git).
4. Build with `UNITY_DIRECT_ENABLED=true`.
5. Test: force AdMob no-fill, show a Unity test ad, confirm the wallet credit
   after the S2S callback.

## Tests

- Dart unit: fallback decision (AdMob shown → no Unity; AdMob error + flag on →
  Unity; flag off → no Unity).
- Native: manual QA with Unity test mode (initialize, load, show, completed,
  skipped, failure).
- PHP: assert-based HMAC, duplicate `oid`, and daily-cap self-check.
- Regression: `flutter analyze`, `flutter test`, `php -l`.

## Risks

- Unity S2S enablement is external and may take days.
- Direct Unity and AdMob mediation share the SDK; the separate placement and
  `isInitialized()` guard are mandatory.
- A direct Unity ad that completes but whose S2S callback fails leaves the user
  without coins. Keep the flag off until the endpoint is live.
- The AdMob account assessment remains; direct Unity is separate demand, not a
  fix.
- If Unity no longer allows a direct/waterfall placement, C is not viable; fall
  back to B.
