# Reel Activity Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Activity page in the inbox for reel like/comment/reply notifications, plus one-level replies in the reel comments sheet, in-app only.

**Architecture:** A MySQL table `app_reel_notifications` holds per-user activity with `read_at`; the PHP API creates rows best-effort beside likes/comments and serves list/read endpoints; the Flutter inbox gains a Messages/Activity tab and routes taps to the existing reel screen with an optional auto-open comments flag. All social data stays in the existing MySQL API; no push/FCM work.

**Tech Stack:** Flutter 3.47.6 in CI (local 3.50.1), Dart records, `cached_network_image`, PHP 8 + PDO MySQL, plain-PHP self-check tests.

**Spec:** `docs/superpowers/specs/2026-11-27-reel-activity-notifications-design.md`

## Global Constraints

- In-app only. No device push, no new dependency.
- One like notification per `(recipient, actor, reel)` ever — unlike → re-like must not notify again.
- Replies are one level: `parent_id` on a parent that is itself a reply is rejected with `invalid_parent`.
- No notification for your own like/comment/reply.
- Hidden/deleted reel or invisible actor ⇒ notification excluded from the list and from `unreadCount`; no anonymous actor fallback in this list.
- Notification writes are best-effort (`try/catch` + `error_log`); a missing table must never block a like or comment.
- Account deletion removes notifications where recipient = user, actor = user, or reel belongs to user, before the raw reel delete.
- Bottom-nav inbox badge stays **chat-unread only**; activity unread is shown on the Activity tab.
- API lives in gitignored `ghosst-web/` (uploaded to Hostinger). Backend/SQL tasks end with verification, **not** a git commit; only tracked Flutter/docs files are committed.
- Flutter gates: `flutter analyze`, `flutter test`, `flutter build apk --release --flavor direct` (local Flutter 3.50.1 needs `--android-skip-build-dependency-validation`).
- PHP gate: run from `D:\key-mobile\ghosst\ghosst-web\api`: `php tests/social_test.php` and `php tests/reel_notifications_test.php`.

## Review Focus

Each line below is pinned to a test in the owning task.

1. Re-like after unlike must not notify twice — Task 3: `re-like after unlike does not create a second notification`.
2. Reply to a reply must be rejected — Task 3: `reply to a reply is rejected with invalid_parent`.
3. Invisible actor/reel must not leak into the list or unread count — Task 2: `list drops notifications whose reel or actor is no longer visible`.
4. Account deletion must purge notifications on the user's reels between other users — Task 1: `account deletion purges notifications for deleted reels`.
5. Missing table must not break likes/comments — Task 3: `notification write failure does not break like or comment`.

---

### Task 1: SQL migration and deletion cleanup

**Files:**
- Create: `ghosst-web/database/mobile_app_reel_notifications.sql`
- Modify: `ghosst-web/api/routes/account.php` (reel social cleanup block, around lines 323–331)
- Modify: `ghosst-web/api/routes/reels.php:242` (`reels_delete`)
- Test: `ghosst-web/api/tests/social_test.php` (account-deletion assertion, around line 569)

**Interfaces:**
- Consumes: existing `app_reel_comments`, `app_reels`, `app_reel_likes` schema.
- Produces: table `app_reel_notifications` with `id, recipient_id, actor_id, reel_id, comment_id NOT NULL DEFAULT '', type ENUM('like','comment','reply'), text_snapshot, read_at, created_at`, unique key `(recipient_id, actor_id, reel_id, type, comment_id)`; `parent_id CHAR(36) NULL` added to `app_reel_comments`; three cleanup DELETE statements.

- [ ] **Step 1: Write the failing test**

In `social_test.php`, extend the existing account-deletion assertion to also require `DELETE FROM app_reel_notifications` with `recipient_id`, `actor_id`, and `reel_id IN (SELECT id FROM app_reels WHERE user_id = ?)`, and add a check that `routes/reels.php` contains a notification delete keyed by `reel_id`. Add a check that the migration file contains `uq_reel_notif_once` and the guarded `parent_id` column.

- [ ] **Step 2: Run it to verify it fails**

Run from `ghosst-web/api`: `php tests/social_test.php`
Expected: FAIL on the new assertions.

- [ ] **Step 3: Add the migration and cleanup statements**

`mobile_app_reel_notifications.sql`: rerunnable `ALTER TABLE app_reel_comments ADD COLUMN parent_id ...` guarded by `information_schema.COLUMNS`, then the `CREATE TABLE IF NOT EXISTS` from the spec. `account.php`: add the three notification DELETEs alongside the existing `app_reel_comments` deletes, before reels are removed. `reels.php`: inside the existing transaction before commit, add `run_sql('DELETE FROM app_reel_notifications WHERE reel_id = ?', [$id])`.

- [ ] **Step 4: Run it to verify it passes**

Run: `php tests/social_test.php`
Expected: PASS with the original assertions still green.

- [ ] **Step 5: Verify, do not commit**

`git status --short` must show no new tracked files for this task (`ghosst-web/` is gitignored). Record that the SQL must be run on Hostinger before deploying the API.

---

### Task 2: Notification store, list, and read endpoints

**Files:**
- Create: `ghosst-web/api/routes/reel_notifications.php`
- Modify: `ghosst-web/api/index.php` (routes near `reel_social` routes, around line 132)
- Modify: `ghosst-web/api/README.md` (`routes/*.php` and test table)
- Create: `ghosst-web/api/tests/reel_notifications_test.php`

**Interfaces:**
- Consumes: `one()`, `all_rows()`, `scalar()`, `run_sql()`, `read_json()`, `iso_time()`, `social_public_user()`, `social_pagination()` (all existing in `api/lib/`).
- Produces:
  - `reel_notification_create(string $recipientId, string $actorId, string $reelId, string $type, string $commentId = '', string $text = ''): void` — best-effort `INSERT IGNORE`, skip when `$recipientId === $actorId`, catch + `error_log` on failure.
  - `reels_notifications_list(array $ctx): array` → `{ok, notifications:[{id,type,actor,reelId,commentId,text,createdAt,isRead}], unreadCount, nextOffset}`; inner join visible reel (reuse `reel_visible_where('r')`) and non-deleted/non-banned actor; `unreadCount` from the same filtered rows.
  - `reels_notifications_read(array $ctx): array` → `{ok, unreadCount}`; optional body `id` marks one row, otherwise all rows of the recipient.
  - Routes: `GET /v1/me/reel-notifications` → `reels_notifications_list`; `POST /v1/me/reel-notifications/read` → `reels_notifications_read`, both `required`.

- [ ] **Step 1: Write the failing tests**

Create `tests/reel_notifications_test.php` with its own minimal fakes (same pattern as `social_test.php`). Assert:
  - `reel_notification_create('42','7','r1','like')` inserts one row with `comment_id === ''`; same call twice inserts once; `reel_notification_create('42','42',...)` inserts nothing; when `run_sql` throws for the notification table, the function does not rethrow.
  - `list drops notifications whose reel or actor is no longer visible`: fake rows include one visible and two invisible (hidden reel, banned actor); expect only the visible one in `notifications` and `unreadCount === 1`.
  - `read marks one row when id is supplied and all rows otherwise`: assert `read_at` updated only for the targeted row, and the returned `unreadCount`.

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/reel_notifications_test.php`
Expected: FAIL because `reel_notifications.php` does not exist.

- [ ] **Step 3: Implement the three functions and register the routes**

Write the functions in the new route file following the existing route style (`ApiError`, `now_utc()`, `uuid4()`), add the two `ROUTES` entries in `index.php`, and add the new test/route file to `api/README.md`.

- [ ] **Step 4: Run it to verify it passes**

Run: `php tests/reel_notifications_test.php`
Expected: PASS.

- [ ] **Step 5: Verify, do not commit**

`git status --short` unchanged for this task. No tracked files.

---

### Task 3: Wire likes, comments, and replies to notifications

**Files:**
- Modify: `ghosst-web/api/routes/reel_social.php` (`reels_like`, `reels_comments_create`, `reels_comments_list`)
- Modify: `ghosst-web/api/tests/reel_notifications_test.php` (also `require ../routes/reel_social.php`)

**Interfaces:**
- Consumes: `reel_notification_create(...)` from Task 2; existing `reel_comment_validate`, `reel_visible_where`, `social_pagination`.
- Produces: `POST /v1/reels/{id}/comments` accepts `parentId`; comments list rows carry `parentId` and `replyTo` (empty string when parent author is invisible); like/comment create notification calls.

- [ ] **Step 1: Write the failing tests**

Add to `reel_notifications_test.php` (assert on recorded SQL/params, not on mocks' call counts):
  - `re-like after unlike does not create a second notification`: call like twice with an intervening unlike; expect one notification insert.
  - `self like and self comment create no notification`.
  - `comment notifies reel owner and reply notifies parent author`: parent author ≠ owner ≠ actor ⇒ two rows (`comment` and `reply`), each `comment_id` = new comment id, text snapshot ≤ 300 chars.
  - `reply to a reply is rejected with invalid_parent`: parent row has non-empty `parent_id`.
  - `parent from another reel is rejected`.
  - `notification write failure does not break like or comment`: make the notification fake throw; like/comment still return success.
  - `comments list maps parentId and replyTo`.

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/reel_notifications_test.php`
Expected: FAIL on the new assertions.

- [ ] **Step 3: Implement the wiring**

In `reels_like`: use the affected-row count of the existing `INSERT IGNORE` into `app_reel_likes`, fetch the reel owner id, and call `reel_notification_create` only for a new, non-self like. In `reels_comments_create`: validate `parentId` (exists, `status='visible'`, same reel, parent `parent_id` empty) with `invalid_parent`/`comment_not_found`; store `parent_id`; call `reel_notification_create` for owner and parent author as specified. In `reels_comments_list`: left-join parent comment author, select `p.user_id` / `pu.display_name`, map `parentId` and `replyTo` (empty when invisible).

- [ ] **Step 4: Run it to verify it passes**

Run: `php tests/reel_notifications_test.php` then `php tests/social_test.php`
Expected: both PASS, including the pre-existing social assertions.

- [ ] **Step 5: Verify, do not commit**

No tracked files changed.

---

### Task 4: Flutter models and Backend methods

**Files:**
- Modify: `lib/services/models.dart` (`ReelComment`, new `ReelNotification`)
- Modify: `lib/services/worker_backend.dart`
- Test: `test/social_models_test.dart`

**Interfaces:**
- Consumes: none from earlier tasks at compile time (API payloads are plain JSON).
- Produces:
  - `ReelComment` gains `final String parentId` and `final String replyTo`, both defaulting to `''` in the constructor and parsed tolerantly in `fromJson`.
  - `class ReelNotification { final String id, type, reelId, commentId, text, createdAt; final PublicUser actor; final bool isRead; factory fromJson(Map<String,dynamic>) }`
  - typedef-like record type used everywhere: `({List<ReelNotification> notifications, int unreadCount, int nextOffset})`.
  - `Backend.reelNotifications({int limit = 20, int offset = 0})` → `Future<({List<ReelNotification> notifications, int unreadCount, int nextOffset})>` via `GET /me/reel-notifications`.
  - `Backend.markReelNotificationsRead({String? id})` → `Future<int>` (unreadCount) via `POST /me/reel-notifications/read`.
  - `Backend.reel(String id)` → `Future<Reel>` via `GET /reels/$id`, mapping `res['reel']`.

- [ ] **Step 1: Write the failing tests**

In `test/social_models_test.dart`: `ReelComment.fromJson` maps `parentId`/`replyTo` and tolerates missing values; `ReelNotification.fromJson` maps every field, tolerates a missing actor, and defaults `isRead` to false.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/social_models_test.dart`
Expected: FAIL (named parameters/type not defined).

- [ ] **Step 3: Implement the models and Backend methods**

Update the two model classes and add the three `Backend` methods next to the existing reel methods (~lines 556–606). Keep `parentId`/`replyTo` in the exact form the API emits.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/social_models_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/models.dart lib/services/worker_backend.dart test/social_models_test.dart
git commit -m "feat: reel activity models and backend endpoints"
```

---

### Task 5: Activity tab in the inbox

**Files:**
- Modify: `lib/screens/inbox_screen.dart`
- Test: `test/direct_chat_inbox_test.dart` (extend `_pump` helper with the new optional callbacks)

**Interfaces:**
- Consumes: `ReelNotification` and the record from Task 4; `Backend.reelNotifications` / `Backend.markReelNotificationsRead` as defaults.
- Produces: `InboxScreen` optional params `loadReelNotifications`, `markReelNotificationsRead`, `onOpenReelNotification` (callback shape `void Function(String reelId, {required bool openComments})`); keys `inbox-tab-messages`, `inbox-tab-activity`, `inbox-activity-badge`, `inbox-notification-<id>`, `inbox-notifications-read-all`, `inbox-notifications-empty`, `inbox-notifications-retry`.

- [ ] **Step 1: Write the failing tests**

Add tests to `direct_chat_inbox_test.dart`:
  - `activity tab lists notifications with unread dots and badge`: two fake rows, one read; expect the badge text `1`, both rows, and one unread dot.
  - `mark all read clears unread state`: tap `inbox-notifications-read-all`, expect the injected marker called with no `id`, badge gone, dots gone.
  - `tapping a comment notification routes to reel comments`: expect callback receives the reel id and `openComments == true`; a `like` row gives `false`.
  - `activity load failure shows retry without breaking messages`: fake loader throws; tap Retry recovers; Messages tab still lists threads.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/direct_chat_inbox_test.dart`
Expected: FAIL on the new tests.

- [ ] **Step 3: Implement the Activity page**

Add a compact Messages/Activity tab row above the existing body; keep the circle shelf and DM list inside Messages. Activity shows a header with **Mark all read**, then a `ListView` of `GlowCard` rows (actor name, action text, time, unread dot), plus empty/error/retry states. Defaults call `Backend`. Tapping a row calls the injected route callback with `openComments: type != 'like'` and marks that row read by id. `onUnreadChanged` remains chat-only.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/direct_chat_inbox_test.dart`
Expected: PASS, including the old DM tests.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/inbox_screen.dart test/direct_chat_inbox_test.dart
git commit -m "feat(inbox): activity tab for reel notifications"
```

---

### Task 6: Notification tap routing and auto-open comments

**Files:**
- Modify: `lib/main.dart` (`InboxScreen` wiring, `_openCreatorReel` around line 877)
- Modify: `lib/screens/reels_screen.dart` (`openCommentsOnLoad`)
- Test: `test/reels_screen_test.dart`

**Interfaces:**
- Consumes: `onOpenReelNotification` from Task 5, `Backend.reel` from Task 4, `_openCreatorReel` in `main.dart`.
- Produces: `ReelsScreen.openCommentsOnLoad` (bool, default false), `_openCreatorReel(Reel reel, {bool openComments = false})`; the comments sheet opens at most once per requested reel id.

- [ ] **Step 1: Write the failing tests**

Add to `reels_screen_test.dart`: with `initialReelId: 'r1'` and `openCommentsOnLoad: true`, after `_settle` expect the comments sheet (`ValueKey('reel-comments-sheet')`) present; trigger a refresh (`refreshToken` bump) and expect exactly one sheet; with `openCommentsOnLoad: false`, expect no sheet.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/reels_screen_test.dart`
Expected: FAIL on the new test.

- [ ] **Step 3: Wire the route and the flag**

In `ReelsScreen`, add the optional constructor field and a one-shot flag guard around the existing `_openComments(reel)` after a successful load. In `main.dart`, pass `onOpenReelNotification` to the embedded `InboxScreen` in `HomeShell` (around line 1077); `_openInbox()` only switches tabs and needs no change. The callback loads the reel with `Backend.reel(id)`, then calls `_openCreatorReel(reel, openComments: openComments)`. Forward the flag to `ReelsScreen` inside `_openCreatorReel`.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/reels_screen_test.dart test/home_shell_navigation_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/screens/reels_screen.dart test/reels_screen_test.dart
git commit -m "feat(reels): open reel and comments from activity"
```

---

### Task 7: Reply action in the comments sheet

**Files:**
- Modify: `lib/screens/reel_comments_screen.dart`
- Test: `test/reel_comments_screen_test.dart` (extend `_pump` with `submitReply`)

**Interfaces:**
- Consumes: `ReelComment.parentId` / `replyTo` from Task 4; `submit(text)` existing callback.
- Produces: `ReelCommentsScreen.submitReply` optional `Future<void> Function(String parentId, String text)?`; keys `comment-reply-<commentId>`, `comment-reply-banner`, `comment-reply-cancel`, `comment-reply-label-<commentId>`.

- [ ] **Step 1: Write the failing tests**

Add to `reel_comments_screen_test.dart`:
  - `reply action sets a target and submits with parentId`: tap `comment-reply-Nice`, expect `comment-reply-banner` text contains `@Jeric`, type text, tap `reel-comments-send`, expect `submitReply` called once with `('Nice', 'hello')` and `submit` not called.
  - `cancel clears the reply target`: tap Reply then `comment-reply-cancel`, expect no banner and next send uses `submit`.
  - `inline reply label uses server replyTo`: a comment with `replyTo: 'Jeric'` shows `Replying to @Jeric`.
  - `missing submitReply falls back to plain submit`: existing behavior unchanged.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/reel_comments_screen_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement the reply UI**

Add a `Reply` action under each comment row, a reply-target banner above the composer with a cancel button, and a different hint while replying. `_submit()` calls `submitReply(parentId, text)` when a target is set and the callback exists, otherwise `submit(text)`; reload comments as today. Render the inline `Replying to @<replyTo>` text when `replyTo` is non-empty.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/reel_comments_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit and run full gates**

```bash
git add lib/screens/reel_comments_screen.dart test/reel_comments_screen_test.dart
git commit -m "feat(reels): reply to comments"
```
Then run: `flutter test`, `flutter analyze`, `flutter build apk --release --flavor direct --android-skip-build-dependency-validation`, and both PHP self-checks from `ghosst-web/api`.
