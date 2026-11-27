# Reel posting ban (temporary / permanent) — design

**Date:** 2026-11-27
**Status:** awaiting approval

## Intent / why

The owner needs to stop a user from posting reels without suspending their
whole account: they may keep browsing, chatting, liking, and commenting. The
ban should be time-boxed from the website admin (with a permanent option).

## Goals

1. Website admin can ban/unban a user **from posting reels only**, with a
   duration of 1 day, 7 days, 30 days, or Permanent.
2. API refuses `POST /v1/reels/uploads` and `POST /v1/reels/{id}/complete`
   while the ban is active, with a clear `403 reels_post_banned` error.
3. The app shows a calm, understandable message for that error.
4. Expiry is automatic — no cron job, no admin cleanup needed.

## Non-goals / anti-goals

- No change to the existing full-account ban (`users.is_banned`), sign-in,
  browsing, chat, likes, comments, follows, or reports.
- No in-app admin UI — the control lives in the existing website admin
  (`admin/users.php`), where account bans already live.
- No per-ban reason/history table; the admin action log is the record.
- No blocking of reel uploads already persisted before the ban took effect
  beyond refusing the completion call.

## Constraints

- `users` already has `chat_muted` / `muted_until` — the new field follows that
  single-column, timestamp-based pattern.
- `reels_upload_init` and `reels_upload_complete_locked` lock the user row with
  `SELECT ... FOR UPDATE`; the ban check must use that same locked read.
- API is uploaded manually from `ghosst-web/api/`; DB changes are manual SQL
  files in `ghosst-web/database/` run on Hostinger.
- Before the migration is run, all new code must fail open (ban not enforced),
  not throw a missing-column 500 — same lesson as the recent `parent_id` bug.

## Approaches

Chosen: **one `users.reels_banned_until DATETIME NULL` column**. Admin sends a
duration; PHP computes the UTC expiry (far-future date for Permanent, `NULL`
for unban). The API checks the locked user row at upload init and completion.
Smallest complete change, no new table, automatic expiry.

Rejected: a dedicated `app_reel_post_bans` table (auditable but more files and
a bigger migration); a settings JSON map keyed by user id (no migration but
unstructured, race-prone, needs account-deletion cleanup); reusing
`is_banned` (would suspend the whole account — explicitly not wanted).

## Design

### 1. SQL migration — `ghosst-web/database/mobile_app_reel_post_ban.sql`

Rerunnable guarded `ALTER TABLE users ADD COLUMN reels_banned_until DATETIME NULL`
using `information_schema.COLUMNS` (same style as
`mobile_app_profile_fields.sql`). No index needed (one row lookup by PK).

### 2. API — `ghosst-web/api/routes/reels.php`

- Add `function reels_post_ban_active(array $account): bool` — returns true
  only when `reels_banned_until` parses to a time in the future. If the field
  is absent (migration not run), return false.
- `reels_upload_init`: extend the locked user-row SELECT to include
  `reels_banned_until`; after the existing `is_banned` check, throw
  `new ApiError(403, 'reels_post_banned', 'Posting reels is temporarily disabled for your account.')`.
- `reels_upload_complete_locked`: extend its `SELECT id FROM users ... FOR UPDATE`
  to include `reels_banned_until` and apply the same check, so a ban imposed
  mid-upload cannot publish the reel.
- To avoid a missing-column SQL error before migration, build the column list
  via `social_column_exists(T_USERS, 'reels_banned_until')` (cached helper in
  `lib/social.php`) and omit the field when absent.

### 3. App message — `lib/api/api_exception.dart`

Add a `forbidden` case: `'reels_post_banned' => 'You cannot post reels right now. You can still browse and chat.'`
Add a focused assertion in `test/api_exception_test.dart`.

### 4. Website admin — `ghosst-web/admin/users.php`

- Add POST action `toggle_reel_ban` with `user_id` and `duration` in
  `1d|7d|30d|permanent|none`. Compute UTC timestamp with
  `gmdate('Y-m-d H:i:s', time() + $seconds)`; permanent uses
  `2099-12-31 23:59:59`; `none` sets `NULL`.
- Guard the column on read/write with a `SHOW COLUMNS FROM users LIKE
  'reels_banned_until'` check so the admin page still works before migration.
- Add a "Ban from reels" / "Unban reels" action button in the user row and a
  modal with a duration `<select>` (1/7/30 days, Permanent). Show a small
  "Reels banned" badge in the status cell while active; no reason input.
- Log with `logAdminAction(..., 'ban_reels' / 'unban_reels', ...)` and flash a
  confirmation message.

### 5. Tests / verification

- `ghosst-web/api/tests/social_test.php`: add cases to the existing reel upload
  checks — active `reels_banned_until` → `403 reels_post_banned` on both init
  and complete; expired/null → allowed; absent field → allowed; migration file
  contains `reels_banned_until` and the guarded `ALTER`.
- `php tests/social_test.php` plus the other API self-checks.
- `flutter test test/api_exception_test.dart` and full `flutter test`.
- Website has no browser harness here; after upload, manually ban a test user
  for 1 day and confirm they can still browse/chat but cannot upload.

### 6. Rollout

1. Run the SQL migration on Hostinger.
2. Upload `api/` and `admin/users.php`.
3. Ship the Flutter change for the friendly message (optional for enforcement).

## Left to the builder

Exact badge color, modal copy, and test-key names are builder calls. Permanent
is represented as a far-future timestamp, not a second column.
