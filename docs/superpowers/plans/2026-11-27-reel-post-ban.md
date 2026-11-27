# Reel Post Ban Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the website admin temporarily or permanently ban a user from posting reels while leaving browsing, chat, likes, and comments intact.

**Architecture:** One nullable `users.reels_banned_until` timestamp (mirroring `muted_until`) is written by the website admin. The PHP API checks the locked user row at reel upload init and completion and returns `403 reels_post_banned`; the app maps that code to a friendly message. No new table, no cron job.

**Tech Stack:** PHP 8 API (`ghosst-web/api/`), manual MySQL migration (`ghosst-web/database/`), website admin `admin/users.php`, Flutter `lib/api/api_exception.dart`, plain-PHP and Flutter widget/unit tests.

**Spec:** `docs/superpowers/specs/2026-11-27-reel-post-ban-design.md`

## Global Constraints

- No change to `users.is_banned`, sign-in, browsing, chat, likes, comments, follows, or reports.
- Permanent is a far-future timestamp `2099-12-31 23:59:59`, not a second column.
- Before the migration is run, all new code fails open (ban not enforced), never a missing-column 500.
- Error code `reels_post_banned`, status 403, message `Posting reels is temporarily disabled for your account.`
- App user message: `You cannot post reels right now. You can still browse and chat.`
- Admin durations: `1d|7d|30d|permanent|none`; `none` sets `NULL`; UTC timestamps via `gmdate('Y-m-d H:i:s', ...)`.
- New admin button follows the existing `role !== 'admin'` guard — admins cannot be reel-banned from the UI.
- Website/API/DB files are gitignored and deployed by upload: those tasks end with verification, not a git commit.

## Review Focus

1. Active ban blocks reel upload init — Task 1: `active ban blocks upload init`.
2. Ban imposed during an upload blocks completion — Task 2: `ban is rechecked at completion`.
3. Missing column fails open — Task 1: `missing ban column allows upload`.
4. Expired timestamp allows posting again — Task 1: `expired ban allows upload`.
5. Admin cannot be reel-banned from the admin UI — Task 4: `admin users cannot be reel-banned`.

---

### Task 1: Migration + upload-init guard

**Files:**
- Create: `ghosst-web/database/mobile_app_reel_post_ban.sql`
- Modify: `ghosst-web/api/routes/reels.php` (`reels_upload_init`, new helper)
- Test: `ghosst-web/api/tests/social_test.php`

**Interfaces:**
- Consumes: `social_column_exists()` from `api/lib/social.php`, fake `one()` in `social_test.php`.
- Produces: `reels_post_ban_active(array $account): bool` in `routes/reels.php` (true only when `reels_banned_until` parses to a future time; false when absent).

- [ ] **Step 1: Write the failing tests**

In `social_test.php`, set `$GLOBALS['social_user_row']` to a row with `reels_banned_until` in the future and call `reels_upload_init` with a valid body/headers (reuse the existing upload test setup). Add four checks:
  - `active ban blocks upload init` — `api_error(..., 403, 'reels_post_banned')`.
  - `expired ban allows upload` — past timestamp returns `ok`.
  - `missing ban column allows upload` — row without the field returns `ok`.
  - migration file contains `reels_banned_until` and `information_schema.COLUMNS`.

- [ ] **Step 2: Run it to verify it fails**

Run from `ghosst-web/api`: `php tests/social_test.php`
Expected: FAIL on the new assertions (helper/code missing).

- [ ] **Step 3: Implement the helper and init guard**

Write `reels_post_ban_active()`; in `reels_upload_init`, build the locked user-row SELECT column list with `social_column_exists(T_USERS, 'reels_banned_until')` so the field is only selected when present, and after the `is_banned` check throw `new ApiError(403, 'reels_post_banned', 'Posting reels is temporarily disabled for your account.')` when the helper returns true. Add the rerunnable guarded `ALTER TABLE users ADD COLUMN reels_banned_until DATETIME NULL` migration.

- [ ] **Step 4: Run it to verify it passes**

Run: `php tests/social_test.php`
Expected: PASS with all pre-existing assertions green.

- [ ] **Step 5: Verify, do not commit**

`git status --short` unchanged for this task (`ghosst-web/` is gitignored).

---

### Task 2: Completion guard

**Files:**
- Modify: `ghosst-web/api/routes/reels.php` (`reels_upload_complete_locked`)
- Test: `ghosst-web/api/tests/social_test.php`

**Interfaces:**
- Consumes: `reels_post_ban_active()` from Task 1.
- Produces: ban rechecked before a pending reel becomes visible.

- [ ] **Step 1: Write the failing test**

In `social_test.php`, set a future `reels_banned_until` on the locked user row used by `reels_upload_complete` and assert `api_error(fn () => reels_upload_complete(...), 403, 'reels_post_banned')` — name it `ban is rechecked at completion`.

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/social_test.php`
Expected: FAIL (completion still succeeds).

- [ ] **Step 3: Apply the same guard**

Extend the `SELECT id FROM users ... FOR UPDATE` in `reels_upload_complete_locked` with the column guarded by `social_column_exists()`, then throw the same `reels_post_banned` error before any media/commit work.

- [ ] **Step 4: Run it to verify it passes**

Run: `php tests/social_test.php`
Expected: PASS, including the original completion/replay assertions.

- [ ] **Step 5: Verify, do not commit**

No tracked files changed.

---

### Task 3: App-facing message

**Files:**
- Modify: `lib/api/api_exception.dart` (`userMessage`, forbidden switch)
- Modify: `test/api_exception_test.dart`
- Commit: yes.

**Interfaces:**
- Consumes: API code `reels_post_banned` from Tasks 1–2.
- Produces: exact `userMessage` string for that code.

- [ ] **Step 1: Write the failing test**

Add to `api_exception_test.dart`: build/parse a `403` envelope with `code: 'reels_post_banned'` (following the existing `account_banned` test pattern) and assert `api.userMessage == 'You cannot post reels right now. You can still browse and chat.'`.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/api_exception_test.dart`
Expected: FAIL (returns generic forbidden text).

- [ ] **Step 3: Add the mapping**

In the `ApiErrorKind.forbidden` switch, add the `reels_post_banned` case with the exact string above.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/api_exception_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/api/api_exception.dart test/api_exception_test.dart
git commit -m "feat(reels): friendly message for reel post ban"
```

---

### Task 4: Website admin control

**Files:**
- Modify: `ghosst-web/admin/users.php` (POST switch ~20–36, user row SELECT ~103, status cell ~219–227, action group ~228–238, modal ~293–317, JS ~362–369)
- Test: `ghosst-web/api/tests/social_test.php` (source assertions, like prior website tasks)

**Interfaces:**
- Consumes: `users.reels_banned_until` from Task 1 migration.
- Produces: `toggle_reel_ban` POST action with `user_id` + `duration`; buttons `Ban from reels` / `Unban reels`; keys `reel-ban-<id>`, `reel-ban-modal`, `reel-ban-duration`.

- [ ] **Step 1: Write the failing tests**

Append source assertions to `social_test.php`: `users.php` contains `toggle_reel_ban`, `reels_banned_until`, `reel_ban_column_exists(`, `role !== 'admin'` near the new button, `logAdminAction(` with `'ban_reels'`, and a `<select name="duration"` with value `permanent`.

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/social_test.php`
Expected: FAIL on the admin assertions.

- [ ] **Step 3: Implement the admin action and UI**

Add helper `reel_ban_column_exists($pdo): bool` (SHOW COLUMNS guard) so the page works before migration. Add POST case `toggle_reel_ban`: validate `duration` against `1d|7d|30d|permanent|none`, compute UTC expiry (permanent = `2099-12-31 23:59:59`, none = `NULL`), update only when the column exists, log with `ban_reels`/`unban_reels`, and flash confirmation. Add `reels_banned_until` to the user-list SELECT only when the column exists. Add an action button (inside the existing `role !== 'admin'` guard) and a modal with a duration `<select>` (1 day / 7 days / 30 days / Permanent); show a "Reels banned" badge while active.

- [ ] **Step 4: Run it to verify it passes**

Run: `php tests/social_test.php` then `php -l ghosst-web/admin/users.php` (from repo root)
Expected: PASS, no syntax errors.

- [ ] **Step 5: Final gates and rollout note**

Run all PHP self-checks from `ghosst-web/api` and `flutter test`. Upload the migration SQL (run it first), then `api/` and `admin/users.php`, then the Flutter build. Manual smoke test: ban a test user 1 day → browse/chat still work → upload rejected with the friendly message → expiry restores posting.
