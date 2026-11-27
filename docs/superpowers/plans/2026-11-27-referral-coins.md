# Referral Coins (app-only) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move referral earning out of the website and into the app, where entering an inviter's code credits the inviter 100 coins.

**Architecture:** The PHP API owns all coin writes: `POST /v1/me/referral` validates a `REF-XXXXXX` code, locks the caller row, records one `referrals_tracker` row and increments the referrer's `users.coins` inside a transaction. The Flutter app exposes the user's own code and a claim sheet; website earning/claim code is deleted while `referral_balance` stays frozen and still spendable at checkout.

**Tech Stack:** PHP 8.1 + MySQL (Hostinger/Laragon), Flutter/Dart, Dio, `share_plus`.

**Spec:** `docs/superpowers/specs/2026-11-27-referral-coins-design.md`

## Global Constraints

- Reward is exactly **100** app coins, referrer only; no invitee reward.
- Code format is exactly `REF-[A-Z2-9]{6}` (same alphabet as `unique_referral_code()`).
- One claim per account; self-referral and deleted referrer rejected.
- Coins are mutated only server-side; never write `coins` from Flutter.
- `users.referral_balance` is frozen: no new earning, still visible and spendable via `checkout.php`.
- API source lives at `ghosst-web/api/` (uploaded to Hostinger); no new DB table or migration.
- Do not run `flutter run`; verify with `flutter analyze`, `flutter test`, `flutter build`.
- CI pins Flutter 3.47.6; do not hand-bump the build number in `pubspec.yaml`.

## Review Focus

- **Self-referral:** entering your own code must credit nobody — Task 1 pins it with a curl smoke against two seeded users, expecting `404 referral_code_not_found` and unchanged coins.
- **Replay:** a second claim by the same invitee must not credit twice — Task 1 curl smoke expects `409 referral_already_claimed` on retry.
- **Deleted/tombstoned referrer:** a code whose user has `deleted_at` set must be rejected — Task 1 curl smoke expects `404`.
- **Concurrent double-claim:** two simultaneous requests from one account must yield one credit — Task 1 implements `SELECT ... FOR UPDATE` on the caller row before reading the tracker; the code is reviewed against the claims.php lock-order pattern.
- **Frozen website balance:** deleting referral earning must not break checkout spending of `referral_balance` — Task 2 keeps `checkout.php`, `referral_coin_rate`, `allow_referral_pay` and asserts they still contain `referral_balance`.

---

### Task 1: API referral claim endpoint

**Files:**
- Modify: `ghosst-web/api/config.php`
- Modify: `ghosst-web/api/routes/account.php` (`account_me`, new `me_claim_referral`)
- Modify: `ghosst-web/api/index.php` (`ROUTES`)

**Interfaces:**
- Consumes: `read_json()`, `ApiError`, `one()`, `scalar()`, `run_sql()`, `db()`, `now_utc()`, `T_USERS` (all existing).
- Produces: `POST /v1/me/referral` returning `{"ok":true,"reward":100}`; `GET /v1/me` user payload gains `referralCode: string`.

- [ ] **Step 1: Add the reward constant**

In `ghosst-web/api/config.php`, next to `COINS_PER_REWARD`, add:
`define('REFERRAL_COINS_REWARD', 100);`

- [ ] **Step 2: Expose the code in `/v1/me`**

In `account_me()`, add `referral_code` to the SELECT and add `'referralCode' => (string) $row['referral_code'],` to the `user` payload.

- [ ] **Step 3: Write `me_claim_referral(array $ctx): array` in `routes/account.php`**

Signature and behavior:
- `$uid = (string) ($ctx['user']['id'] ?? '')`; empty → `ApiError(401, 'auth', 'Not signed in')`.
- `$code = strtoupper(trim((string) (read_json()['code'] ?? '')))`; if `!preg_match('/^REF-[A-Z2-9]{6}$/', $code)` → `ApiError(400, 'invalid_referral_code', 'Invalid referral code')`.
- `db()->beginTransaction()`; in `try`:
  1. `SELECT id FROM users WHERE id = ? AND deleted_at IS NULL FOR UPDATE` on `$uid`; missing → `401 unauthorized`.
  2. `SELECT id FROM referrals_tracker WHERE referred_id = ?`; any row → `409 referral_already_claimed`.
  3. `SELECT id FROM users WHERE referral_code = ? AND deleted_at IS NULL` on `$code`; missing or same id as `$uid` → `404 referral_code_not_found`.
  4. `INSERT INTO referrals_tracker (referrer_id, referred_id, referrer_reward, referred_reward) VALUES (?, ?, ?, 0)` with `(int) referrer id, (int) $uid, REFERRAL_COINS_REWARD`.
  5. `UPDATE users SET coins = coins + ? WHERE id = ?` with `(REFERRAL_COINS_REWARD, (int) referrer id)`.
  6. `$pdo->commit()`; `catch (Throwable $e) { $pdo->rollBack(); throw $e; }`.
- Return `['ok' => true, 'reward' => REFERRAL_COINS_REWARD]`.

- [ ] **Step 4: Register the route**

In `index.php` `ROUTES`, next to `GET /v1/me`, add:
`['POST', '#^/v1/me/referral$#', 'me_claim_referral', 'required'],`

- [ ] **Step 5: Lint and smoke-test**

Run:
Run from the repo root:
```powershell
php -l ghosst-web/api/config.php
php -l ghosst-web/api/routes/account.php
php -l ghosst-web/api/index.php
```
Expected: `No syntax errors detected` for each.

Then, with the local server running (`php -S 127.0.0.1:8099 -t C:\laragon\www\api C:\laragon\www\api\index.php`):
- `curl -X POST http://127.0.0.1:8099/v1/me/referral -H 'Content-Type: application/json' -d '{"code":"BAD"}'` → HTTP **401** (route exists, auth required).
- With a valid bearer token, `{"code":"BAD"}` → **400** `invalid_referral_code`.
- With a token for seeded user A and A's own code → **404** `referral_code_not_found`, A's coins unchanged.
- With user B claiming A's code → **200** `{"ok":true,"reward":100}`; A's `coins` +100; repeat → **409** `referral_already_claimed`, A's coins unchanged.

- [ ] **Step 6: Commit**

```bash
git add ghosst-web/api/config.php ghosst-web/api/routes/account.php ghosst-web/api/index.php
git commit -m "feat(api): add referral claim endpoint that credits 100 coins"
```

---

### Task 2: Remove website-side referral earning

**Files:**
- Modify: `ghosst-web/ajax/auth.php`
- Modify: `ghosst-web/auth/google-callback.php`
- Modify: `ghosst-web/includes/db_config.php`
- Delete: `ghosst-web/ajax/redeem_referral.php`, `ghosst-web/referrals.php`
- Modify: `ghosst-web/dashboard.php`, `ghosst-web/gifts.php`, `ghosst-web/profile.php`, `ghosst-web/admin/includes/layout.php`

**Interfaces:**
- Consumes: none.
- Produces: no website code path writes `referral_balance`; `referral_code` still generated for new users.

- [ ] **Step 1: Strip the auto-reward blocks**

In `ajax/auth.php` and `auth/google-callback.php`, delete only the referral-processing section (from the `// Process referral if there is an active referral code` comment through the cookie/session cleanup). Keep the `referral_code` generation and `INSERT` intact.

- [ ] **Step 2: Remove the `?ref=` capture**

In `includes/db_config.php`, delete the `// Session and Cookie capture for referral system` block (the `$_GET['ref']` → `$_SESSION['referred_by']` / `setcookie('referred_by', ...)` code).

- [ ] **Step 3: Delete claim/page and nav links**

Delete the two files. Remove the `<a href="referrals.php" ...>` sidebar links from `dashboard.php`, `gifts.php`, `profile.php`, and `admin/includes/layout.php` (including the surrounding `<li>`/wrapper in the admin layout).

- [ ] **Step 4: Verify removals and frozen behavior**

Run:
Run from the repo root:
```powershell
php -l ghosst-web/ajax/auth.php
php -l ghosst-web/auth/google-callback.php
php -l ghosst-web/includes/db_config.php
php -l ghosst-web/dashboard.php
php -l ghosst-web/gifts.php
php -l ghosst-web/profile.php
php -l ghosst-web/admin/includes/layout.php
```
Expected: `No syntax errors detected` for each.

Then assert with `git grep`:
```powershell
git grep -n "referred_by\|redeem_referral\|href=\"referrals.php\"" -- ghosst-web
```
Expected: no matches (`admin/referrals.php` itself stays).
```powershell
git grep -n "referral_balance" -- ghosst-web/checkout.php
```
Expected: still matches — frozen balance remains spendable.

- [ ] **Step 5: Commit**

```bash
git add -A ghosst-web/ajax ghosst-web/auth ghosst-web/includes ghosst-web/dashboard.php ghosst-web/gifts.php ghosst-web/profile.php ghosst-web/admin/includes/layout.php
git commit -m "refactor(web): remove website referral earning, freeze existing balance"
```

---

### Task 3: Flutter model + backend client

**Files:**
- Modify: `lib/services/worker_backend.dart` (`AppUser`, `_me`, new statics)
- Test: `test/referral_test.dart` (created here, extended in Task 4)

**Interfaces:**
- Consumes: `ApiClient.post` → `Future<Map<String, dynamic>>`.
- Produces: `AppUser.referralCode` (String, default `''`); `Backend.normalizeReferralCode(String) -> String`; `Backend.claimReferral(String) -> Future<int>` (returns `reward`).

- [ ] **Step 1: Write the failing normalization test**

In `test/referral_test.dart`, add a `test` that expects:
```dart
expect(Backend.normalizeReferralCode(' ref-abcd23 '), 'REF-ABCD23');
expect(Backend.normalizeReferralCode('REF-000000'), '');
expect(Backend.normalizeReferralCode(''), '');
expect(Backend.normalizeReferralCode('REF-ABCDEFG'), '');
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/referral_test.dart`
Expected: FAIL (compile error — `normalizeReferralCode` undefined).

- [ ] **Step 3: Implement model + client**

In `worker_backend.dart`:
- `AppUser`: add `this.referralCode = ''` to the const constructor and `final String referralCode;`.
- `_me()`: add `referralCode: u['referralCode'] as String? ?? ''` to the `AppUser(...)` call.
- Add:
```dart
static String normalizeReferralCode(String input) {
  final code = input.trim().toUpperCase();
  return RegExp(r'^REF-[A-Z2-9]{6}$').hasMatch(code) ? code : '';
}

static Future<int> claimReferral(String code) async {
  final res = await _api.post('/me/referral', data: {'code': normalizeReferralCode(code)});
  return res['reward'] as int? ?? REFERRAL_REWARD;
}
```
Define `const int REFERRAL_REWARD = 100;` at file scope in `worker_backend.dart` and use it as the fallback.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/referral_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/worker_backend.dart test/referral_test.dart
git commit -m "feat(app): add referral code model, validation and claim client"
```

---

### Task 4: Referral sheet and Profile wiring

**Files:**
- Create: `lib/screens/referral_sheet.dart`
- Modify: `lib/screens/profile_screen.dart` (import, `_openReferral`, Account group row)
- Test: `test/referral_test.dart` (add widget tests)

**Interfaces:**
- Consumes: `Backend.normalizeReferralCode`, `Backend.claimReferral` (caller passes both as callbacks so tests need no network).
- Produces: `ReferralSheet({required String referralCode, required Future<int> Function(String) onClaim})`.

- [ ] **Step 1: Write the failing widget tests**

In `test/referral_test.dart`, add `testWidgets` cases:
- Pump `MaterialApp(home: ReferralSheet(referralCode: 'REF-ABC234', onClaim: (_) async => 100))`. Expect `find.text('REF-ABC234')`, a field keyed `referral-code-field`, and a button keyed `referral-claim-button`.
- Enter `' ref-abc234 '`, tap the button, expect the captured argument to equal `'REF-ABC234'` and no error text shown.
- Enter `'BAD'`, tap the button, expect `onClaim` was **not** called and `find.text('Invalid referral code')` finds one widget.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/referral_test.dart`
Expected: FAIL (compile error — `ReferralSheet` undefined).

- [ ] **Step 3: Create the sheet**

`ReferralSheet` is a `StatefulWidget` with a `TextEditingController` (disposed in `dispose`). Body uses existing `CardFrame` / `AppText` / `AppSpace` / `AppColors` primitives from `premium.dart` and `theme.dart`:
- Section "Your code" showing `widget.referralCode` (or `'—'` when empty), a Copy button (`Clipboard.setData`) and a Share button (`Share.share('Join me on Ghosst — my referral code: ${widget.referralCode}')`, from `package:share_plus/share_plus.dart`).
- Section "Use a code" with `TextField(key: const Key('referral-code-field'))` and a button keyed `referral-claim-button`.
- `_claim()`: normalize with `Backend.normalizeReferralCode`; if empty, `setState` an `Invalid referral code` error and return. Otherwise `await widget.onClaim(code)`, then show a `SnackBar` with `'Your friend earned 100 coins'` and call `Navigator.of(context).pop()`. On exception, show the error in a SnackBar and stay open.

- [ ] **Step 4: Wire it into Profile**

In `profile_screen.dart`, import `referral_sheet.dart`, add:
```dart
Future<void> _openReferral() async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ReferralSheet(
      referralCode: _user?.referralCode ?? '',
      onClaim: Backend.claimReferral,
    ),
  );
}
```
Add a `_row(icon: Icons.people_outline, label: 'Referral', hint: 'Invite · +100 coins', onTap: _openReferral)` to the Account `_group([...])`, above the Wallet row.

- [ ] **Step 5: Run the referral tests**

Run: `flutter test test/referral_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/referral_sheet.dart lib/screens/profile_screen.dart test/referral_test.dart
git commit -m "feat(app): add referral sheet and profile entry point"
```

---

### Task 5: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all tests pass, including the new referral cases.

- [ ] **Step 3: Release build**

Run: `flutter build apk --release --flavor direct`
Expected: build succeeds with no compile errors.

- [ ] **Step 4: Report**

Report the analyze/test/build results and any remaining manual checks (Hostinger upload of the changed PHP files, live two-user smoke).
