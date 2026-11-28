# Referral Rewards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Credit both referral participants equally from the API and prevent the same email identity from claiming again after account deletion.

**Architecture:** The PHP API locks both user rows in deterministic order, records a hashed email identity in `referrals_tracker`, and credits both balances in one transaction. Flutter only displays the reward returned by the API.

**Tech Stack:** PHP 8.1+, MariaDB/MySQL, PDO, Flutter/Dart, Dio

**Spec:** `docs/superpowers/specs/2026-11-28-referral-rewards-design.md`

## Global Constraints

- Reward is exactly **5 app coins per participant**; both referrer and invitee receive the same amount.
- Coins are mutated only server-side; never write `coins` from Flutter.
- One successful referral claim per normalized email identity, including after delete/re-register.
- Self-referral, malformed codes, duplicate claims, and deleted referrers are rejected without credit.
- Lock user rows in ascending `users.id` order before tracker insertion or coin updates.
- `users.referral_balance` remains frozen; no website earning changes.
- API source lives at the gitignored `ghosst-web/api/` deploy tree and is uploaded manually to Hostinger; backend edits are not committed to this app repo.
- Do not run `flutter run`; verify with `flutter analyze`, `flutter test`, and PHP syntax/self-checks.

## Review Focus

- **Delete + re-register with the same email:** must return `409 referral_already_claimed` and credit neither account — Task 2.
- **Two concurrent claims from one identity:** caller row lock plus unique email-hash index must allow one credit — Task 2.
- **Reciprocal claims (A invites B while B invites A):** ascending user-row lock order must avoid a lock-order deadlock — Task 2.
- **Deleted referrer:** code lookup must reject the tombstoned owner and leave balances unchanged — Task 2.
- **Server reward amount changes:** Flutter must display the API value, never a local `100` fallback — Task 4.

---

### Task 1: Persistent referral identity migration and helpers

**Files:**
- Create: `ghosst-web/database/mobile_app_referral_identity.sql`
- Modify: `ghosst-web/api/routes/account.php`
- Create: `ghosst-web/api/tests/referral_test.php`

**Interfaces:**
- Produces: `referral_identity_hash(?string $email): ?string`
- Produces: `ensure_referral_identity_column(): void`
- Consumes: existing `db()`, `scalar()`, `run_sql()`, `sha256_hex()`, `T_USERS`

- [ ] **Step 1: Write failing PHP identity tests**

Create `ghosst-web/api/tests/referral_test.php` with minimal DB/API stubs and assertions:

```php
check(referral_identity_hash(' User@Example.com ') === sha256('user@example.com'), 'email hash is normalized');
check(referral_identity_hash(null) === null, 'missing email has no identity');
check(referral_identity_hash('user@example.com') !== 'user@example.com', 'raw email is not stored');
```

Run: `php ghosst-web/api/tests/referral_test.php`
Expected: FAIL because `referral_identity_hash()` does not exist.

- [ ] **Step 2: Add the migration**

Create `ghosst-web/database/mobile_app_referral_identity.sql`:
- Add `referrals_tracker.referred_email_hash CHAR(64) NULL` if missing.
- Add unique index `uq_referred_email` if missing.
- Backfill active tracker rows with `LOWER(SHA2(LOWER(TRIM(users.email)), 256))`.

- [ ] **Step 3: Implement the helpers**

In `ghosst-web/api/routes/account.php`:
- `referral_identity_hash(?string $email): ?string` returns null for empty email, otherwise `sha256_hex(strtolower(trim($email)))`.
- `ensure_referral_identity_column(): void` checks `information_schema`, adds the column/index lazily, and backfills active rows. DDL must run before any claim transaction.

Run: `php ghosst-web/api/tests/referral_test.php`
Expected: PASS.

- [ ] **Step 4: Verify deploy artifacts**

Confirm the migration, route helper, and PHP self-check exist under the gitignored `ghosst-web/` deploy tree. Do not force-add them to the app repository.

---

### Task 2: Equal backend credit and duplicate/reuse protection

**Files:**
- Modify: `ghosst-web/api/routes/account.php`
- Test: `ghosst-web/api/tests/referral_test.php`

**Interfaces:**
- Consumes: Task 1 helpers and existing `POST /v1/me/referral` route.
- Produces: success `{"ok":true,"reward":5}` where `reward` is credited to each participant.

- [ ] **Step 1: Add failing claim-transaction tests**

Extend the fake DB test harness to cover:
- Valid claim: tracker row has `referrer_reward = 5`, `referred_reward = 5`, and the caller email hash; both users gain 5 coins.
- Existing `referred_id`: `409 referral_already_claimed`, no coin update.
- Existing `referred_email_hash` under another user id: `409 referral_already_claimed`, no coin update.
- Self code: `404 referral_code_not_found`.
- Deleted referrer: `404 referral_code_not_found`.
- Malformed code: `400 invalid_referral_code`.
- Lock query uses ascending ids and `ORDER BY id FOR UPDATE`.

Run: `php ghosst-web/api/tests/referral_test.php`
Expected: FAIL on equal credit, email-hash dedupe, and deterministic locking.

- [ ] **Step 2: Rewrite `me_claim_referral()` transaction**

In `ghosst-web/api/routes/account.php`:
1. Validate code and load active caller/referrer before locking.
2. Lock both ids with one ascending `ORDER BY id FOR UPDATE` query; revalidate active rows and referrer code.
3. Compute the caller email hash and reject an existing tracker row matching either `referred_id` or `referred_email_hash`.
4. Insert both reward values as `REFERRAL_COINS_REWARD`.
5. Update referrer and invitee coins inside the same transaction.
6. Commit or roll back; return the configured reward.

- [ ] **Step 3: Run backend referral tests**

Run: `php ghosst-web/api/tests/referral_test.php`
Expected: PASS with all success and rejection cases.

- [ ] **Step 4: Run PHP syntax checks**

```powershell
php -l ghosst-web/api/routes/account.php
php -l ghosst-web/api/tests/referral_test.php
```

Expected: `No syntax errors detected` for both.

- [ ] **Step 5: Verify deploy artifacts**

Re-run the PHP self-check and syntax check; leave the updated backend files in the gitignored deploy tree for manual Hostinger upload.

---

### Task 3: Preserve referral identity during account deletion

**Files:**
- Modify: `ghosst-web/api/routes/account.php`
- Test: `ghosst-web/api/tests/referral_test.php`

**Interfaces:**
- Produces: `referral_preserve_identity(int $uid): void`
- Consumes: Task 1 helpers; called by `account_remove()` before email anonymisation.

- [ ] **Step 1: Write failing deletion-identity test**

Assert that `referral_preserve_identity($uid)`:
- Reads the current email.
- Updates matching tracker rows with its normalized hash.
- Does not delete the tracker row.

Run: `php ghosst-web/api/tests/referral_test.php`
Expected: FAIL because the helper does not exist.

- [ ] **Step 2: Implement and wire the helper**

Add `referral_preserve_identity(int $uid): void` and call it inside `account_remove()` before the `UPDATE users SET deleted_at = ..., email = ...` statement. Keep the existing transaction and tombstone behavior.

- [ ] **Step 3: Run backend tests and syntax check**

Run: `php ghosst-web/api/tests/referral_test.php`
Expected: PASS.

Run: `php -l ghosst-web/api/routes/account.php`
Expected: `No syntax errors detected`.

- [ ] **Step 4: Verify deploy artifacts**

Re-run the PHP self-check and syntax check; keep the deletion change in the gitignored deploy tree for manual upload.

---

### Task 4: Flutter uses the server reward and documents the contract

**Files:**
- Modify: `lib/services/worker_backend.dart`
- Modify: `lib/screens/referral_sheet.dart`
- Modify: `test/referral_test.dart`
- Modify: `ghosst-web/api/README.md`

**Interfaces:**
- Produces: `Backend.claimReferral(String code) -> Future<int>` using only the API `reward`.
- Produces: referral success copy using the returned amount for both participants.

- [ ] **Step 1: Write failing widget test**

Change the claim-success test fake to return `137` and assert the snackbar text:

```dart
expect(find.text('You and your friend earned 137 coins each'), findsOneWidget);
```

Run: `flutter test test/referral_test.dart`
Expected: FAIL because the sheet currently says `Your friend earned 100 coins`.

- [ ] **Step 2: Remove the client reward constant and use the response**

In `lib/services/worker_backend.dart`:
- Delete `const int referralReward = 100`.
- Return `res['reward'] as int` from `claimReferral()`; do not fall back to a local amount.
- Update the method comment to say both participants are credited by the API.

In `lib/screens/referral_sheet.dart`:
- Capture the returned reward and show `You and your friend earned $reward coins each`.

- [ ] **Step 3: Add the API documentation**

Document in `ghosst-web/api/README.md`:
- Both participants receive the same server-configured amount.
- `reward` is per participant.
- Email-hash dedupe survives account deletion.
- Run `database/mobile_app_referral_identity.sql` during deploy.

- [ ] **Step 4: Run Flutter verification**

```powershell
flutter test test/referral_test.dart
flutter analyze
flutter test
```

Expected: referral tests pass; no new analyzer issues; full Flutter suite passes.

- [ ] **Step 5: Commit**

```bash
git add lib/services/worker_backend.dart lib/screens/referral_sheet.dart test/referral_test.dart docs/superpowers/specs/2026-11-28-referral-rewards-design.md docs/superpowers/plans/2026-11-28-referral-rewards.md
git commit -m "feat(app): display server referral reward for both users"
```

---

## Final verification

- [ ] Run all PHP API self-checks: `php ghosst-web/api/tests/referral_test.php` plus existing `php ghosst-web/api/tests/*_test.php`.
- [ ] Confirm `referrals_tracker` has `referred_email_hash` and unique index `uq_referred_email`.
- [ ] Two-user smoke: both balances increase by 5; replay is blocked.
- [ ] Delete/re-register smoke with the same email: second claim is blocked.
- [ ] Confirm website `referral_balance` checkout behavior is unchanged.
