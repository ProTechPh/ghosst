# Reel activity notifications + comment replies — design

**Date:** 2026-11-27
**Status:** awaiting approval

## Intent / why

A user should know when someone likes or comments on their reels, without the
inbox becoming a long mixed list. The inbox gets a second page for activity;
replies to other people's comments are a first-class action and also generate
activity. Everything is **in-app only** — no FCM/Novu push work (explicitly
confirmed by the owner).

## Goals

1. New **Activity** page inside `InboxScreen` (alongside Messages), reachable
   from the existing inbox tab — no new bottom-nav tab.
2. Notifications for: like on your reel, comment on your reel, reply to your
   comment. Tap a like → open that reel; tap a comment/reply → open that reel
   with the comments sheet open.
3. Unread dot per notification, unread count badge on the Activity tab, and a
   **Mark all read** action.
4. Reply button on every comment in the reel comments sheet; reply is stored as
   one level of `parent_id` and shows "Replying to @name".

## Non-goals / anti-goals

- No device push notifications, no new notification dependency.
- No nested/threaded replies deeper than one level, no reactions, no per-item
  delete, no admin UI for notifications.
- No notification for your own like/comment/reply; no duplicate like
  notification when a user re-likes after unliking.
- No PII in payloads (actor = public profile fields only), no client-side
  mutation of coins/stock.

## Constraints

- API is the PHP 8 tree at `ghosst-web/api/` (uploaded to Hostinger); no
  backend build from the Flutter repo. PHP self-checks run with
  `php ghosst-web/api/tests/social_test.php`.
- DB changes are **manual SQL migrations** run on Hostinger. New file:
  `ghosst-web/database/mobile_app_reel_notifications.sql`, rerunnable
  (`CREATE TABLE IF NOT EXISTS`, guarded `ALTER`).
- Flutter gates: `flutter analyze`, `flutter test` (account for existing
  splash timings; pump explicit durations), `flutter build` instead of
  `flutter run`.
- Existing inbox is embedded in `HomeShell`'s IndexedStack and has an
  `onUnreadChanged` callback that currently means **chat** unread only.

## Approaches (decided)

Chosen: **Activity tab inside InboxScreen + MySQL notification table +
one-level `parent_id` replies.** The inbox screen stays short, all social data
stays in the same MySQL store, per-row `read_at` supports both unread dots and
mark-all-read, and replies stay a simple parent pointer. Rejected: separate
full-screen page (more nav wiring for the same result), expanding the global
announcements card (does not fix length, no per-user read state), deriving
notifications from likes/comments queries (cannot remember what was read),
Firestore (inconsistent with reel data).

## Design

### 1. SQL migration (`mobile_app_reel_notifications.sql`)

```sql
ALTER TABLE app_reel_comments
  ADD COLUMN parent_id CHAR(36) NULL COMMENT 'one-level reply target';

CREATE TABLE IF NOT EXISTS app_reel_notifications (
  id            CHAR(36) PRIMARY KEY,
  recipient_id  INT UNSIGNED NOT NULL,
  actor_id      INT UNSIGNED NOT NULL,
  reel_id       CHAR(36) NOT NULL,
  comment_id    CHAR(36) NOT NULL DEFAULT '',
  type          ENUM('like','comment','reply') NOT NULL,
  text_snapshot VARCHAR(300) NOT NULL DEFAULT '',
  read_at       DATETIME NULL,
  created_at    DATETIME NOT NULL,
  UNIQUE KEY uq_reel_notif_once (recipient_id, actor_id, reel_id, type, comment_id),
  KEY idx_reel_notifs_recipient (recipient_id, created_at DESC, id),
  KEY idx_reel_notifs_reel (reel_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

`comment_id` is `''` for likes (not NULL), so MySQL's unique key also dedupes
likes: a user gets **at most one like notification per reel, ever**, even after
unlike → re-like. Notification inserts use `INSERT IGNORE`; the like handler
still checks the like insert's affected rows before trying. Rerunnable `ALTER`:
use an `information_schema.COLUMNS` guard (same style as other migrations in
`ghosst-web/database/`).

Cleanup: `routes/account.php` deletes rows where `recipient_id = uid`,
`actor_id = uid`, **or** `reel_id IN (SELECT id FROM app_reels WHERE user_id = ?)`
— the last one is required because account deletion removes the user's reels
directly instead of calling `reels_delete()`. Do this before deleting the
reels. `routes/reels.php` deletion also deletes rows where `reel_id = id`. The
app's account-deletion promise stays intact.

### 2. PHP API

- `GET /v1/me/reel-notifications?limit=20&offset=0` (`required`) →
  `{ok, notifications:[{id,type,actor,reelId,commentId,text,createdAt,isRead}],
  unreadCount, nextOffset}`. Inner-join a **visible** reel (with visible media)
  and a non-deleted, non-banned actor, matching `reels_comments_list()`. Rows
  whose reel or actor is no longer visible are dropped from the list **and**
  from `unreadCount`, so no dead links or stale PII survive. Reuse
  `social_public_user()` and `iso_time()`; no anonymous fallback here.
- `POST /v1/me/reel-notifications/read` (`required`) with optional body
  `{id}` → marks that one row read when `id` is present, otherwise all rows of
  the recipient; returns `{ok, unreadCount}`.
- `POST /v1/reels/{id}/comments` accepts optional `parentId`. Inside the
  existing user-row-locking transaction: validate the parent exists, is
  `visible`, belongs to the same reel, **and is itself not a reply**
  (`parent_id` empty — reject with `invalid_parent` to keep depth at one);
  insert the comment with `parent_id`; create notifications:
  - reel owner when actor != owner: `type = parentId ? 'reply' : 'comment'`,
    `comment_id` = new comment id.
  - parent comment author when different from actor and from owner:
    `type = 'reply'`, same `comment_id`.
  Text snapshot = first 300 chars of the new comment.
- `reels_like` creates a `like` notification only on a genuinely new like
  (`INSERT IGNORE` affected row) and when actor != reel owner.
- Notification writes are **best-effort**: a small `try/catch` + `error_log`
  wrapper, so a missing table (migration not yet run) cannot block a like or
  comment. The comment's own insert stays transactional; notification failure
  never rolls it back.
- Comments list joins the parent author and returns `replyTo` (display name,
  empty when that author is no longer visible) plus `parentId` for one-level
  display.

### 3. Flutter

- `lib/services/models.dart`: `ReelComment` gains `parentId` and `replyTo`;
  new `ReelNotification` with `fromJson`. Both tolerant of missing/invalid
  fields, following the existing model style.
- `lib/services/worker_backend.dart`: `reelNotifications({limit, offset})`,
  `markReelNotificationsRead({String? id})`, `reel(String id)` (GET
  `/v1/reels/{id}`, maps `reel`). All network access stays here.
- `lib/screens/inbox_screen.dart`: new optional constructor callbacks/
  loaders (`loadReelNotifications`, `markReelNotificationsRead`,
  `onOpenReelNotification`) so existing tests and callers need no changes.
  Adds a small Messages/Activity tab row; Activity shows notification rows
  (actor name, action text, time, unread dot), **Mark all read** in the header,
  empty/error/retry states. Tapping a row calls
  `onOpenReelNotification(reelId, openComments: type != 'like')` and marks that
  row read. The tab shows an unread badge. Existing `onUnreadChanged` keeps
  meaning "chat unread"; the bottom nav badge is unchanged (builder call).
- `lib/main.dart`: wire the new callbacks; notification tap loads the reel via
  `Backend.reel(id)` and reuses `_openCreatorReel(reel, openComments: ...)`
  (new optional flag) so the existing initial-reel ordering logic is kept.
- `lib/screens/reels_screen.dart`: optional `openCommentsOnLoad`; once the
  requested reel is in the feed, open its comments sheet exactly once.
- `lib/screens/reel_comments_screen.dart`: `Reply` action per comment sets a
  reply target; composer shows "Replying to @name" with a cancel button and a
  different hint. Submit uses optional `submitReply(parentId, text)` when
  provided, else `submit(text)`, then reloads comments as today. Inline
  `Replying to @name` uses the server-provided `replyTo`.

### 4. Tests / verification

- PHP: extend `ghosst-web/api/tests/social_test.php` for reply validation,
  parent mismatch rejection, notification creation rules (no self, no
  duplicate like, reply-to-author + owner), list/read mapping.
- Flutter: `test/reels_screen_test.dart` (open-comments-on-load),
  `test/reel_comments_screen_test.dart` (reply target + submit), and
  `test/direct_chat_inbox_test.dart` (Activity tab, unread badge, mark all
  read, tap routing). Keep existing assertions intact.
- Gates: focused tests → full `flutter test` → `flutter analyze` →
  `flutter build apk --release --flavor direct` (local Flutter 3.50.1 needs
  `--android-skip-build-dependency-validation`; CI pins 3.47.6) →
  `php ghosst-web/api/tests/social_test.php`.

### 5. Rollout

1. Run the SQL migration on Hostinger.
2. Upload the updated `api/` folder.
3. Ship the Flutter release; without the migration the Activity tab simply
   shows an error/retry state and Messages keeps working, and likes/comments
   still succeed (best-effort notification writes).

## Left to the builder

Concrete test-key names, exact error strings, small UI copy, and the PHP
fake-DB details needed by the self-check are builder calls. The one item
marked "builder call" above (bottom-nav badge stays chat-only) is settled as
written unless the owner objects.

## Reviewer decisions folded in

- Like notification is **once per actor + reel, ever** (unique key + `INSERT
  IGNORE`); unlike → re-like does not notify again.
- Invisible reel/actor rows are dropped from both the list and `unreadCount`;
  no anonymous actor fallback in this list.
- A reply to a reply is rejected (`invalid_parent`).
- Account deletion purges notifications on the user's reels even between two
  other people, before the raw reel delete.
- Notification writes never block likes/comments; they are caught + logged.
