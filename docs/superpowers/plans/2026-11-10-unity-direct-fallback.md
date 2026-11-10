# Unity Ads Direct Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When AdMob has no fill or fails, show a rewarded Unity ad directly and credit coins only after Unity's server-to-server callback verifies the view.

**Architecture:** A new Kotlin `MethodChannel` drives the Unity Ads SDK already bundled by `gma_mediation_unity`; a Dart service exposes `showRewarded`. `EarnScreen` tries AdMob first and calls the Unity path only when AdMob is unavailable and `UNITY_DIRECT_ENABLED` is on. A new PHP route verifies Unity's HMAC-MD5 S2S callback and credits coins through the existing `app_ad_rewards` ledger and `reward_verdict` pacing.

**Tech Stack:** Flutter/Dart, Kotlin/Android, Unity Ads Android SDK 4.20.1, PHP 8, MySQL.

**Spec:** `docs/superpowers/specs/2026-11-10-unity-direct-fallback-design.md`

## Global Constraints

- `UNITY_DIRECT_ENABLED` defaults to **false**. Enable only after Unity Support confirms S2S and `UNITY_S2S_SECRET` is set.
- Unity Game ID: `800392172`. Direct placement: `BP_Rewarded_Direct` (must be created in the Unity dashboard; override with `--dart-define=UNITY_REWARDED_PLACEMENT=` if named differently).
- `gma_mediation_unity` 1.11.1 (adapter 4.20.1.0) is already in `pubspec.yaml`. Add `com.unity3d.ads:unity-ads:4.20.1` to the app module so Kotlin can compile direct calls.
- The mediated Unity placement (`BP_Rewarded_Android`) must never be used by the direct path — use the separate direct placement.
- Coins are credited only by the PHP S2S endpoint; never from a Dart callback alone.
- `app_ad_rewards.id` is `varchar(100)`; use `u_<oid>` for Unity rewards.
- `ghosst-web/` is gitignored. Deploy `ghosst-web/api/*` manually after changes.
- No new dependency for the Unity SDK beyond the app-module `implementation` line; the mediation plugin already ships it.

## Review Focus

- **AdMob fills normally:** the Unity fallback must never run. The AdMob callbacks set a "shown/earned" flag before any fallback decision.
- **AdMob no-fill, flag off:** no Unity call, same user-facing error as today.
- **AdMob no-fill, flag on:** exactly one Unity attempt per tap; a second `onError` must not start another ad.
- **Unity completes but S2S is slow/fails:** no client-side credit, no duplicate reward. The wallet poll may time out; coins arrive only after the S2S row is inserted.
- **Bad HMAC / duplicate `oid` / daily cap:** no credit; Unity gets a non-retryable 200 (`1`) on duplicate/cap, 403 on bad HMAC.

---

### Task 1: Backend Unity S2S endpoint

**Files:**
- Modify: `ghosst-web/api/config.php` (add `UNITY_S2S_SECRET`)
- Modify: `ghosst-web/api/lib/rewards.php` (add `unity_s2s_signature`)
- Modify: `ghosst-web/api/routes/ads.php` (add `ads_unity_s2s`)
- Modify: `ghosst-web/api/index.php` (route)
- Create: `ghosst-web/api/tests/unity_s2s_test.php`
- Test: `php ghosst-web/api/tests/unity_s2s_test.php`

**Interfaces:**
- Consumes: `T_USERS`, `T_REWARDS`, `COINS_PER_REWARD`, `REWARD_WINDOW_SECONDS`, `reward_verdict()`, `to_epoch()`, `sha256_hex()`, `one()`, `run_sql()`, `db()`, `log_line()`, `log_guard()`.
- Produces:
  - `unity_s2s_signature(array $params, string $secret): string`
  - `ads_unity_s2s(array $ctx): RawResponse`
  - Route `GET /v1/ads/unity-s2s`

- [ ] **Step 1: Write the failing signature test**

`ghosst-web/api/tests/unity_s2s_test.php`:

```php
<?php
declare(strict_types=1);

require __DIR__ . '/../config.php';
require __DIR__ . '/../lib/rewards.php';

function check(bool $ok, string $label): void
{
    if (!$ok) {
        fwrite(STDERR, "FAIL: {$label}\n");
        exit(1);
    }
}

$params = ['sid' => 'user-1', 'oid' => 'offer-1'];
$expected = hash_hmac('md5', 'oid=offer-1,sid=user-1', 'test-secret');
check(unity_s2s_signature($params, 'test-secret') === $expected, 'sorted signature');
check(
    unity_s2s_signature(['hmac' => 'ignored'] + $params, 'test-secret') === $expected,
    'hmac is excluded'
);
echo "ok\n";
```

- [ ] **Step 2: Run it to verify it fails**

Run: `php ghosst-web/api/tests/unity_s2s_test.php`
Expected: FAIL / fatal because `unity_s2s_signature` does not exist.

- [ ] **Step 3: Add the helper to `lib/rewards.php`**

```php
/**
 * Unity Ads S2S signature: all query params except `hmac`, sorted
 * alphabetically, joined as key=value with commas, HMAC-MD5 with the secret
 * Unity Support provided.
 */
function unity_s2s_signature(array $params, string $secret): string
{
    unset($params['hmac']);
    ksort($params);
    $parts = [];
    foreach ($params as $key => $value) {
        $parts[] = $key . '=' . (string) $value;
    }
    return hash_hmac('md5', implode(',', $parts), $secret);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `php ghosst-web/api/tests/unity_s2s_test.php`
Expected: `ok`

- [ ] **Step 5: Add the config constant**

In `ghosst-web/api/config.php`, next to the AdMob SSV config:

```php
/** Unity Ads S2S secret (from Unity Ads Support). Empty = fallback disabled. */
define('UNITY_S2S_SECRET', getenv('GHOSST_UNITY_S2S_SECRET') ?: '');
```

- [ ] **Step 6: Add the endpoint to `routes/ads.php`**

Implement `ads_unity_s2s(array $ctx): RawResponse`:

- If `UNITY_S2S_SECRET === ''`, log and return `503` `not configured`.
- Read `sid`, `oid`, `hmac`; require non-empty, else `400`.
- `hash_equals(unity_s2s_signature($_GET, UNITY_S2S_SECRET), $hmac)`; on mismatch log and return `403`.
- Look up `app_users` by `sid` (`deleted_at IS NULL`); unknown → `404`.
- `$txId = 'u_' . $oid;` insert into `app_ad_rewards` with `ad_unit = 'unity_direct'`, `reward = min(COINS_PER_REWARD, MAX_REWARD)`, `event_time`/`created_at` = UTC now, `email_hash` from the user's email. `ON DUPLICATE KEY UPDATE id = id`; if `rowCount() === 0`, return `200` + `1` (duplicate).
- Count the ledger in `REWARD_WINDOW_SECONDS` using the same `email_hash`/`user_id` predicate as `ads_ssv`; call `reward_verdict()`. If blocked, delete the just-inserted row, `log_guard()`, return `200` + `1`.
- Update `app_users.coins = coins + reward`; if `rowCount() === 0`, delete the ledger row and return `200` + `1`.
- On DB failure, delete the ledger row, `log_line()`, return `500`.
- Success: `new RawResponse('1', 200, 'text/plain; charset=utf-8')`.

- [ ] **Step 7: Register the route**

In `index.php` `ROUTES`, next to the AdMob SSV route:

```php
['GET', '#^/v1/ads/unity-s2s$#', 'ads_unity_s2s', 'none'],
```

- [ ] **Step 8: Lint and re-run the self-check**

Run:
```
php -l ghosst-web/api/config.php
php -l ghosst-web/api/lib/rewards.php
php -l ghosst-web/api/routes/ads.php
php -l ghosst-web/api/index.php
php ghosst-web/api/tests/unity_s2s_test.php
```
Expected: all `No syntax errors` and `ok`.

- [ ] **Step 9: Commit**

```bash
git add ghosst-web/api/config.php ghosst-web/api/lib/rewards.php ghosst-web/api/routes/ads.php ghosst-web/api/index.php ghosst-web/api/tests/unity_s2s_test.php
git commit -m "feat(api): add Unity Ads S2S reward endpoint"
```

---

### Task 2: Android Unity Ads bridge

**Files:**
- Modify: `android/app/build.gradle.kts` (app-module Unity SDK dependency)
- Modify: `android/app/src/main/kotlin/com/astrixtech/ghosst/MainActivity.kt`

**Interfaces:**
- Produces: `MethodChannel("com.astrixtech.ghosst/unityads")`
  - `initialize` args `{gameId: String, testMode: Boolean}` → Bool
  - `load` args `{placementId: String}` → Bool
  - `show` args `{placementId: String, userId: String}` → Bool
  - Native → Dart `event` with `{type: "loaded"|"loadFailed"|"shown"|"completed"|"skipped"|"failed"|"closed", message?: String}`

- [ ] **Step 1: Add the compile-time Unity SDK dependency**

In `android/app/build.gradle.kts`, after `flutter { source = "../.." }`:

```kotlin
dependencies {
    // Direct Kotlin calls need the SDK on the app's compile classpath; the
    // gma_mediation_unity plugin keeps its copy implementation-only.
    implementation("com.unity3d.ads:unity-ads:4.20.1")
}
```

- [ ] **Step 2: Add the channel and handlers in `MainActivity.kt`**

In `configureFlutterEngine`, create and store a channel:

```kotlin
private var unityChannel: MethodChannel? = null

val unity = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UNITY_CHANNEL)
unityChannel = unity
unity.setMethodCallHandler { call, result ->
    when (call.method) {
        "initialize" -> { /* gameId + testMode; skip if UnityAds.isInitialized() */ }
        "load" -> { /* placementId; complete result on loaded/failed */ }
        "show" -> { /* placementId + userId; set PlayerMetaData; show */ }
        else -> result.notImplemented()
    }
}
```

Implement `emitUnityEvent(type, message)` that calls
`unityChannel?.invokeMethod("event", mapOf("type" to type, "message" to message))`.

Use these Unity 4.20.1 APIs:

```kotlin
UnityAds.initialize(this, gameId, testMode, object : IUnityAdsInitializationListener { ... })
UnityAds.load(placementId, UnityAdsLoadOptions(), object : IUnityAdsLoadListener { ... })
UnityAds.show(this, placementId, UnityAdsShowOptions(), object : IUnityAdsShowListener { ... })
UnityAds.isInitialized()
PlayerMetaData(this).apply { setServerId(userId) }.commit()
```

Callbacks:
- Initialization: complete the `initialize` result on `onInitializationComplete`, error on `onInitializationFailed`.
- Load: complete the `load` result on `onUnityAdsAdLoaded`, error on `onUnityAdsFailedToLoad`.
- Show: set `PlayerMetaData` before `UnityAds.show`; complete the `show` result on `onUnityAdsShowStart`; emit `completed` on `UnityAdsShowCompletionState.COMPLETED`, `skipped` on `SKIPPED`, `failed` on `onUnityAdsShowFailure`, and `closed` from a small delay after completion/skip (or emit `closed` immediately after the completion event). If `onUnityAdsShowFailure` fires before `show` completes, complete the result with an error.

Match the SDK's nullable `String?` message parameters. Do not complete a `MethodChannel.Result` twice.

- [ ] **Step 3: Build the debug APK**

Run: `flutter build apk --debug --flavor play`
Expected: `Built build\app\outputs\flutter-apk\app-play-debug.apk`

- [ ] **Step 4: Commit**

```bash
git add android/app/build.gradle.kts android/app/src/main/kotlin/com/astrixtech/ghosst/MainActivity.kt
git commit -m "feat(android): add direct Unity Ads bridge"
```

---

### Task 3: Dart Unity direct service

**Files:**
- Create: `lib/services/unity_direct_ads.dart`
- Test: `test/unity_direct_ads_test.dart`

**Interfaces:**
- Consumes: `MethodChannel("com.astrixtech.ghosst/unityads")`, `AdUnits.useTestAds`.
- Produces:
  - `class UnityDirectAds` with `static UnityDirectAds instance`
  - `static bool get enabled` (`debugEnabled || const bool.fromEnvironment('UNITY_DIRECT_ENABLED')`)
  - `static bool isAdMobUnavailable(String error)`
  - `Future<bool> showRewarded({required String userId, required VoidCallback onCompleted, required VoidCallback onClosed, required ValueChanged<String> onError})`
  - `@visibleForTesting static const MethodChannel channel`
  - `@visibleForTesting static bool debugEnabled`
  - `@visibleForTesting static void resetForTest()`

- [ ] **Step 1: Write the failing test**

`test/unity_direct_ads_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/unity_direct_ads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(UnityDirectAds.resetForTest);

  test('defaults to disabled', () {
    expect(UnityDirectAds.enabled, isFalse);
  });

  test('classifies only AdMob availability errors as fallback candidates', () {
    expect(UnityDirectAds.isAdMobUnavailable('No ads available right now.'), isTrue);
    expect(UnityDirectAds.isAdMobUnavailable('Network connection issue.'), isTrue);
    expect(UnityDirectAds.isAdMobUnavailable('Could not play video right now.'), isTrue);
    expect(UnityDirectAds.isAdMobUnavailable('Another advertisement is already displaying.'), isFalse);
  });

  test('returns false without touching the channel when disabled', () async {
    final result = await UnityDirectAds.instance.showRewarded(
      userId: 'u1',
      onCompleted: () {},
      onClosed: () {},
      onError: (_) {},
    );
    expect(result, isFalse);
  });

  test('runs initialize, load and show when enabled', () async {
    UnityDirectAds.debugEnabled = true;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(UnityDirectAds.channel, (call) async {
      calls.add(call.method);
      return true;
    });

    final shown = await UnityDirectAds.instance.showRewarded(
      userId: 'u1',
      onCompleted: () {},
      onClosed: () {},
      onError: (_) {},
    );

    expect(shown, isTrue);
    expect(calls, ['initialize', 'load', 'show']);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/unity_direct_ads_test.dart`
Expected: FAIL because `UnityDirectAds` does not exist.

- [ ] **Step 3: Implement `lib/services/unity_direct_ads.dart`**

Key points:
- `enabled` checks `debugEnabled` first, then the compile-time define.
- `isAdMobUnavailable` lowercases and checks: `no ads available`, `network connection`, `temporarily unavailable`, `still loading`, `could not play video`. It must return false for `another advertisement`.
- `showRewarded`:
  - Return false if `!enabled` or already busy.
  - Set the method-call handler to route native `event` calls to the stored callbacks.
  - `invokeMethod('initialize', {'gameId': gameId, 'testMode': AdUnits.useTestAds})`.
  - `invokeMethod('load', {'placementId': placementId})`.
  - `invokeMethod('show', {'placementId': placementId, 'userId': userId})`; return `true` when the ad starts.
  - Catch `PlatformException`/`MissingPluginException` → call `onError` with a short message, return false.
  - Keep callbacks in fields; clear them on `completed`/`closed`/`failed`.
  - Use `const String.fromEnvironment('UNITY_GAME_ID', defaultValue: '800392172')` and `UNITY_REWARDED_PLACEMENT` default `BP_Rewarded_Direct`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/unity_direct_ads_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/unity_direct_ads.dart test/unity_direct_ads_test.dart
git commit -m "feat: add direct Unity Ads service"
```

---

### Task 4: Earn screen fallback wiring

**Files:**
- Modify: `lib/screens/earn_screen.dart`

**Interfaces:**
- Consumes: `UnityDirectAds.enabled`, `UnityDirectAds.isAdMobUnavailable`, `UnityDirectAds.instance.showRewarded`, `Backend.currentUser()`, existing `_verify()`, `_startCooldown()`.
- Produces: no new public API.

- [ ] **Step 1: Write the failing predicate check**

Add to `test/unity_direct_ads_test.dart` a test that the AdMob "another advertisement" message is not a fallback candidate (already covered) and that the unavailable messages are. This is the decision point for `EarnScreen`.

- [ ] **Step 2: Wire `_watchAd`**

In `EarnScreen`:
- Add `bool _unityFallbackTried = false;` reset at the start of `_watchAd`.
- In the existing `onError` callback, before showing the error:

```dart
if (!_unityFallbackTried &&
    UnityDirectAds.enabled &&
    UnityDirectAds.isAdMobUnavailable(e)) {
  _unityFallbackTried = true;
  unawaited(_watchUnityAd());
  return;
}
```

- Add `_watchUnityAd()`:

```dart
Future<void> _watchUnityAd() async {
  final user = await Backend.currentUser();
  if (!mounted) return;
  if (user == null) {
    setState(() { busy = false; status = 'Sign in first.'; });
    return;
  }
  setState(() => status = 'Loading Unity ad…');
  final shown = await UnityDirectAds.instance.showRewarded(
    userId: user.id,
    onCompleted: () => unawaited(_verify()),
    onClosed: () {
      if (!mounted) return;
      if (status == 'Loading Unity ad…') {
        setState(() {
          busy = false;
          status = 'Ad closed before a reward was earned.';
        });
        _startCooldown(15);
      }
    },
    onError: (e) {
      if (!mounted) return;
      setState(() { busy = false; status = e; });
    },
  );
  if (!shown && mounted && status == 'Loading Unity ad…') {
    setState(() {
      busy = false;
      status = 'Unity ad is not available right now.';
    });
  }
}
```

- Ensure `_verify()` is not called twice: the Unity `onCompleted` is the only trigger; the AdMob `onEarned` path remains separate. `_verify()` already guards `verifying`.

- [ ] **Step 3: Run the analyzer**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 4: Run the chat/earn-related tests**

Run: `flutter test test/unity_direct_ads_test.dart test/ad_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/earn_screen.dart lib/services/unity_direct_ads.dart
git commit -m "feat: fall back to direct Unity when AdMob is unavailable"
```

---

### Task 5: Rollout docs and config

**Files:**
- Modify: `SETUP.md`
- Modify: `ghosst-web/api/README.md`

- [ ] **Step 1: Document the external setup**

In `SETUP.md`, add a section:

```markdown
## Unity Ads direct fallback

1. Unity dashboard: create a rewarded placement `BP_Rewarded_Direct` and note the id.
2. Contact Unity Ads Support for Game ID `800392172` with callback URL
   `https://ghossthub.com/api/v1/ads/unity-s2s`; keep the HMAC secret.
3. Set `UNITY_S2S_SECRET` in `api/config.php` (or `GHOSST_UNITY_S2S_SECRET`).
4. Build with `--dart-define=UNITY_DIRECT_ENABLED=true`. The flag stays off
   until step 2 and 3 are done; otherwise users can watch an ad with no coins.
5. QA: Unity test mode + `--dart-define=USE_TEST_ADS=false
   --dart-define=ADMOB_TEST_DEVICE_IDS=<device-id>
   --dart-define=UNITY_DIRECT_ENABLED=true`.
```

In `ghosst-web/api/README.md`, add the route and secret to the route table /
deployment notes.

- [ ] **Step 2: Commit**

```bash
git add SETUP.md ghosst-web/api/README.md
git commit -m "docs: document Unity direct fallback rollout"
```

---

### Task 6: End-to-end verification

- [ ] **Step 1: Static checks**

```powershell
flutter analyze
php -l ghosst-web/api/config.php
php -l ghosst-web/api/lib/rewards.php
php -l ghosst-web/api/routes/ads.php
php -l ghosst-web/api/index.php
php ghosst-web/api/tests/unity_s2s_test.php
```

- [ ] **Step 2: Flutter tests**

```powershell
flutter test
```

- [ ] **Step 3: Build check**

```powershell
flutter build apk --debug --flavor play
```

- [ ] **Step 4: Manual S2S check with a test user (after the secret is set)**

Compute an HMAC with a test secret and call the endpoint with `sid=<test-user>`,
`oid=test-<timestamp>`. Confirm:
- first call credits `COINS_PER_REWARD`;
- replaying the same `oid` returns `1` and does not credit again;
- a bad `hmac` returns `403`;
- a 41st reward in the 24h window returns `1` without credit.

- [ ] **Step 5: Manual app QA (Unity test mode)**

Build with the QA command, force AdMob no-fill (or use the account limit),
confirm the Unity ad appears, `onCompleted` triggers the wallet poll, and the
S2S row appears in `app_ad_rewards` with `ad_unit = 'unity_direct'`.

- [ ] **Step 6: Commit any verification fixes**

```bash
git add -A
git commit -m "test: verify Unity direct fallback"
```

---

## Self-Review Notes

- **Spec coverage:** app bridge, Dart service, fallback hook, S2S endpoint, flag, rollback, docs, tests.
- **Interfaces:** `unity_s2s_signature`, `ads_unity_s2s`, `UnityDirectAds.showRewarded`, `isAdMobUnavailable`, and the channel methods are named consistently across tasks.
- **Security:** HMAC is verified with `hash_equals`; duplicate `oid` is idempotent; daily cap is shared; no client-side credit.
- **Limits:** The direct Unity path is off by default; it cannot be enabled before the secret and placement exist.
- **External blocker:** Unity Support must enable S2S. If that cannot be done, the flag stays off and the app behaves exactly as today.
