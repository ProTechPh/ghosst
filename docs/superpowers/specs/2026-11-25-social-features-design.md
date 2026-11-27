# Private Chat, Public Profiles, Feedback, and User Reels — Design

Date: 2026-11-25
Status: approved by owner 2026-11-25
Chosen approach: Firebase direct messages + PHP/MySQL social data + self-hosted z.com video files

## 1. Intent and why

Add a small social layer to Ghosst without replacing the existing coin/store app or its
PHP/MySQL backend:

1. **Private chat** between any two signed-in users.
2. **Public user profiles** that can be opened from chat and reels.
3. **In-app feedback** for the Ghosst team.
4. **User-uploaded reels**: an Instagram-inspired, full-screen vertical video feed with
   follows, likes, comments, and reporting.

The owner will host reel video files on **z.com over FTP/HTTPS**. The Android app must
never contain FTP credentials or the video-upload signing secret.

Success means a signed-in user can move from world chat or a reel to another user's
profile, message or follow them, submit feedback, upload a short gallery video, and
interact with reels without leaving the app.

## 2. Approved capability map and build order

| Module id | Responsibility | Depends on |
|---|---|---|
| `private-chat` | 1:1 realtime messages, inbox, unread/read state, block/report entry points | Existing accounts + Firebase custom-token session |
| `public-profiles` | Safe public profile, avatar, join date, follower/reel stats, Message button | Existing accounts |
| `feedback` | Private rating/comment form and own submission history | Existing accounts + `feedbacks` table |
| `social-graph` | Follow/unfollow, followers/following lists and counts | `public-profiles` |
| `reels` | Gallery upload, vertical feed, likes, comments, reports, creator grid, admin moderation | `public-profiles`, `social-graph`, z.com uploader |

Build order: `private-chat` → `public-profiles` → `feedback` → `social-graph` → `reels`.

Each module ships as a separate, verifiable slice. No module may write coins, keys, stock,
or purchase records.

## 3. Goals

- Any signed-in user can start a text-only private conversation with any other signed-in
  user, except where a block exists.
- Private messages update in realtime and remain usable offline through Firestore's local
  queue.
- Public profiles expose only intentional fields: identity, avatar, join date, social
  counts, and public reels. Never expose email, password, balance, purchases, or admin
  contact data.
- Feedback reuses the existing `feedbacks` table and website admin page.
- Every signed-in user can upload gallery videos, subject to size and daily limits.
- Reels support **For You** and **Following** feeds, vertical swipe, muted autoplay, loop,
  like/unlike, comments, follow/unfollow, report, creator profile, and delete-own-reel.
- Admins/moderators can hide/show/delete reels, hide comments, and review reports.
- Account deletion removes the new social/PII stores, including private conversations and
  uploaded reel metadata/files on a best-effort basis.

## 4. Non-goals (v1)

- DM attachments, voice notes, typing indicators, read receipts for individual messages,
  group chats, or DM push notifications.
- Profile editing, bio, cover photo, account switching, or public email addresses.
- Public app reviews: app feedback is **private to the admin team** in v1.
- In-app camera recording, trimming, filters, duets, stitched reels, saved videos, shares,
  exact view counts, or algorithmic recommendations.
- Reel pre-moderation/transcoding service. Reels auto-publish after upload validation and
  are moderated after publication.
- Replacing world chat, the existing website feedback flow, or the current bottom-tab
  store/earn/purchase flows.

## 5. Anti-goals

- No FTP credentials, API secret, JWT secret, or Firebase service-account key in the APK.
- No open Firestore rules and no client-trusted sender/participant identity.
- No public profile response built with `SELECT *`.
- No user-supplied filename or path reaching filesystem deletion/move operations.
- No unbounded list endpoints or video uploads.
- No silent change to the existing public website feedback behavior.
- No manual `version: +N` bump; CI still owns build-number increments.

## 6. Constraints from the repository

- Flutter 3.47.6 / Dart 3.11, Android-only, `play` and `direct` flavors.
- CI gates are `flutter analyze` and `flutter test`; tests must not need network, Firebase,
  a device video plugin, or a live database.
- HTTP access stays behind `lib/services/worker_backend.dart`; shared JSON models live in
  `lib/services/models.dart`.
- The API is plain PHP 8, upload-deployed from `ghosst-web/api/`, with no Composer
  requirement. Use PDO prepared statements and the existing `ApiError` envelope.
- `users.id` is an integer in MySQL but a string in app JSON and Firebase custom-token UID.
- World chat already uses Firebase project `ghosst-6f23e` and a backend-minted custom token.
- Existing Firestore rules are managed in the Firebase console and are not checked into
  the repo. The owner has chosen the new checked-in `firestore.rules` as authoritative;
  it must preserve the documented world-chat contract and be reviewed before publishing.
- The database dump is historical; the new migration file is the source of truth for
  social tables.
- Every push to `main` auto-bumps and publishes. Backend/rules/hosting setup must land
  before the corresponding app slice is merged.

## 7. Approaches considered

### 7.1 Firebase DMs + MySQL social data — chosen

- Firestore handles realtime 1:1 messages using the existing custom-token identity.
- PHP/MySQL handles public profiles, follows, reel metadata, likes, comments, reports, and
  feedback.
- z.com stores video files behind a small signed-upload PHP endpoint.

**Why:** reuses working chat infrastructure, gives realtime/offline DMs without polling
Hostinger, and keeps content/social queries in the existing relational backend.

**Trade-off:** two storage systems and a one-time Firestore rules deployment.

### 7.2 All social data in MySQL

Private messages would use API polling and the existing `chat_messages` table.

**Rejected:** one database is simpler operationally, but chat is not truly realtime, costs
more Hostinger connections, and drains more mobile battery/data.

### 7.3 All social data in Firebase/Firestore

Profiles, follows, reel metadata, likes, and comments would also be Firestore documents.

**Rejected:** realtime is attractive, but complex rules, moderation/deletion, query limits,
Spark quota risk, and duplicated account data make this the expensive path.

## 8. Shared architecture

```text
Android app
  ├─ Firebase Auth custom token ── Firestore: world_chat, direct_threads, user_blocks
  ├─ PHP API (ghossthub.com/api/v1)
  │    └─ MySQL: users + app_follows/app_reels/app_reel_* / feedbacks/app_reports
  └─ signed upload ticket ── z.com/reels/upload.php ── public MP4 files
```

### 8.1 Assumptions and builder calls

These are explicit defaults chosen by the builder, not additional owner requirements:

- DMs are text-only, 1..500 characters, with a 2-second client cooldown.
- Any signed-in user may start a DM; a block prevents new messages in either direction.
- Public profiles have display name, username, avatar, join date, admin/moderator badge,
  follower/following/reel counts, and public reel grid. No bio or edit form in v1.
- App feedback is permanently private (`source = 'app'`, `status = 'hidden'`) and cannot be
  made public from the admin page. Existing website feedback keeps `source = 'website'`.
- Reels auto-publish after validation; moderation is post-publication.
- Upload limit: **50 MB hard cap**, **60-second target**, maximum **5 uploads per rolling
  24 hours per user**.
- Only MP4 (`video/mp4`) is accepted. No camera recording or client-side trimming.
- No DM push notifications or exact reel view counts in v1.
- Deleting an account deletes complete private conversations for both participants, the
  user's follows/likes/comments/reports/reels, private app feedback, and avatar URL. Reel
  file deletion on z.com is best-effort and logged. The Firebase Auth user is also deleted
  best-effort so refresh tokens cannot mint a new session.
- Existing website feedback rows are not bulk-deleted by this project; only rows with
  `source = 'app'` are removed by `DELETE /v1/account`.
- Social feeds and comment lists join `users` and exclude `deleted_at IS NOT NULL` or
  `is_banned = 1`. An already-issued Firebase token can survive a website ban for at most
  its remaining 1-hour lifetime; the app signs out of Firebase as soon as `/me` rejects
  the account.
- The website reels moderation page accepts a union of website `role = 'admin'` and app
  `is_admin`/`is_moderator`, because both refer to the same `users` row. API admin routes
  continue to use the existing app role flags.

## 9. `private-chat`

### 9.1 Firestore data model

```text
direct_threads/{threadId}
  participants: [uidA, uidB]                 // exactly two distinct string UIDs
  lastMessage: string <= 500
  lastMessageAt: serverTimestamp
  lastSenderId: string
  lastReadAt: { uidA: timestamp?, uidB: timestamp? }
  createdAt: serverTimestamp
  updatedAt: serverTimestamp

direct_threads/{threadId}/messages/{messageId}
  senderId: string
  text: string 1..500
  ts: serverTimestamp
```

`threadId` is the two UIDs sorted as strings and joined with `__`. Sorting is only for a
stable ID; rules accept either participant order in the ID and verify it contains exactly
the two participant UIDs.

No display name or email is copied into private messages. The inbox resolves participant
profile data through `GET /v1/users/{id}`.

### 9.2 Rules contract

Add a reviewed `firestore.rules` file (or a merge snippet if the owner keeps console-only
rules) that preserves the existing `world_chat` block and adds:

- `direct_threads/{threadId}` read: authenticated UID is in `participants`, and no block
  exists in either direction.
- Thread create: exactly two distinct participants including `request.auth.uid`; thread ID
  matches those two UIDs; required metadata has the correct types and timestamp.
- Thread update for sending: participants are unchanged; sender is the authenticated UID;
  only `lastMessage`, `lastMessageAt`, `lastSenderId`, and `updatedAt` may change.
- Thread update for read: only the authenticated UID's `lastReadAt` entry and `updatedAt`
  may change.
- Message read: authenticated UID is a participant of the parent thread and no block
  exists.
- Message create: `senderId == request.auth.uid`, parent thread exists, sender is a
  participant, text is 1..500 non-whitespace, `ts == request.time`, and no block exists.
- Message update/delete: denied to clients.
- `user_blocks/{blockerId}/blocked/{blockedId}` read/create/delete: only the authenticated
  owner of `blockerId`; `blockedId` must be a different non-empty string.
- World-chat mute applies only to world chat, not DMs.

### 9.3 Flutter

- `lib/services/direct_chat_service.dart`: injectable `DirectChatClient` with
  `threads()`, `messages(threadId)`, `send()`, `markRead()`, `block()`, and `unblock()`.
- `lib/screens/inbox_screen.dart`: live thread list, last message/time, unread indicator,
  empty/error states.
- `lib/screens/direct_chat_screen.dart`: reversed live message list, composer, profile
  header, block/report actions, offline/pending status.
- `ChatScreen` gains an Inbox button and an unread badge. Tapping a world-chat avatar/name
  opens `UserProfileScreen`; its Message button opens the deterministic DM thread.
- Local unread = `lastMessageAt > lastReadAt[myUid]` and `lastSenderId != myUid`.

### 9.4 Abuse and deletion

- Client cooldown is 2 seconds. Server-side pacing requires Firestore App Check or a
  Cloud Function later; this is a known v1 limit.
- `POST /v1/reports` handles user/message reports in MySQL.
- On account deletion, `firebase_scrub_social(uid)` queries threads where the UID is a
  participant and deletes their message subcollections and thread documents. It then
  calls the Firebase Auth Admin delete-account endpoint with an Identity Toolkit scoped
  access token. Both operations are best-effort after the MySQL commit, with quota
  backoff matching `firebase_scrub_chat()`.
- `ChatService` and `DirectChatService` sign out of Firebase when `Backend.currentUser()`
  returns null, so a banned/deleted account does not keep an app session alive.
- Block relationships owned by the deleted UID are deleted; blocks targeting the UID may
  remain as tombstone handles so the account ID cannot be reused.

## 10. `public-profiles`

### 10.1 Schema

Add to `users`:

```sql
avatar_url VARCHAR(1000) NULL
```

Google sign-in sends the verified Google `photoUrl` to `POST /v1/auth/google`; the API
accepts only HTTPS URLs on `*.googleusercontent.com` and stores the URL. Existing users
receive an avatar on their next Google sign-in. Email-only users keep the initials
fallback.

### 10.2 API

`GET /v1/users/{id}` — authenticated; returns:

```json
{
  "ok": true,
  "user": {
    "id": "42",
    "displayName": "Name",
    "username": "name",
    "avatarUrl": null,
    "createdAt": "2026-01-01T00:00:00.000Z",
    "isAdmin": false,
    "isModerator": false,
    "followerCount": 0,
    "followingCount": 0,
    "reelCount": 0,
    "isFollowing": false,
    "isSelf": false
  }
}
```

`GET /v1/users/{id}/reels?limit=20&offset=0` returns only `visible` reels and the creator's
public profile summary. Unknown/deleted/banned users return 404. No endpoint returns
email, coins, balance, purchases, or ban reason.

### 10.3 UI

`UserProfileScreen` uses the existing dark-neon primitives and shows:

- Avatar or initials, display name, `@username`, admin/moderator badge.
- Member-since date.
- Followers, Following, and Reels counts.
- Follow/Following button for other users; Message button.
- Reel grid with poster or play-placeholder tiles.
- Report and Block actions in the overflow menu.
- Own profile continues to open the existing account `ProfileScreen`.

## 11. `feedback`

### 11.1 Schema and API

Add to `feedbacks`:

```sql
source ENUM('website','app') NOT NULL DEFAULT 'website'
```

Existing rows become `website`. Public website queries must explicitly require
`source = 'website'`; app rows are never public.

`POST /v1/feedback` — authenticated:

```json
{ "comment": "10..1000 characters", "rating": 1 }
```

- Reuse `feedbacks`; insert with `source = 'app'`, `status = 'hidden'`, and
  `image_path = NULL`.
- Validate trimmed UTF-8 length, reject HTML-tag patterns as the website does.
- Rate limit: 5 submissions per rolling 24 hours per user.
- Return `{ok, feedbackId}` using the existing error envelope.

`GET /v1/feedback/mine?limit=20&offset=0` returns the caller's own submissions and status.
The existing `ghosst-web/admin/feedbacks.php` already lists hidden/visible/deleted rows.
Update its Show action so `source = 'app'` rows cannot be made visible, and label them
"Private app feedback". No new admin page is required.

### 11.2 UI

Add **Send feedback** to the existing Profile → App group. `FeedbackScreen` has a 1–5 star
selector, multiline comment, character counter, submit/retry states, and a short own-history
list. Copy states that feedback is sent privately to the Ghosst team.

Telegram notification is not added to the API in v1: the existing helper would delay the
API response, and the admin page already surfaces new rows.

## 12. `social-graph`

### 12.1 Schema

```sql
CREATE TABLE app_follows (
  follower_id INT UNSIGNED NOT NULL,
  creator_id  INT UNSIGNED NOT NULL,
  created_at  DATETIME NOT NULL,
  PRIMARY KEY (follower_id, creator_id),
  KEY idx_follows_creator (creator_id, created_at)
);
```

No self-follow. `app_follows` is independent of DMs: following is not required to message.

### 12.2 API

- `POST /v1/users/{id}/follow` — idempotent `INSERT IGNORE`.
- `DELETE /v1/users/{id}/follow` — idempotent delete.
- Both return `{ok, isFollowing, followerCount}`.
- `GET /v1/users/{id}/followers?limit=20&offset=0`.
- `GET /v1/users/{id}/following?limit=20&offset=0`.
- All require authentication, reject self-follow with 400, and paginate with
  `limit` 1..50 and non-negative `offset`.

## 13. `reels`

### 13.1 MySQL schema

New migration: `ghosst-web/database/mobile_app_social.sql`.

```sql
CREATE TABLE app_reels (
  id           CHAR(36) PRIMARY KEY,
  user_id      INT UNSIGNED NOT NULL,
  caption      VARCHAR(300) NOT NULL DEFAULT '',
  video_url    VARCHAR(1000) NULL,
  storage_key  VARCHAR(255) NULL,
  sha256       CHAR(64) NULL,
  size_bytes   INT UNSIGNED NULL,
  mime_type    VARCHAR(50) NULL,
  duration_ms  INT UNSIGNED NULL,
  poster_url   VARCHAR(1000) NULL,
  status       ENUM('pending','visible','hidden','deleted') NOT NULL DEFAULT 'pending',
  created_at   DATETIME NOT NULL,
  updated_at   DATETIME NOT NULL,
  KEY idx_reels_feed (status, created_at, id),
  KEY idx_reels_user (user_id, status, created_at)
);

CREATE TABLE app_reel_likes (
  reel_id   CHAR(36) NOT NULL,
  user_id   INT UNSIGNED NOT NULL,
  created_at DATETIME NOT NULL,
  PRIMARY KEY (reel_id, user_id),
  KEY idx_likes_user (user_id, created_at)
);

CREATE TABLE app_reel_comments (
  id         CHAR(36) PRIMARY KEY,
  reel_id    CHAR(36) NOT NULL,
  user_id    INT UNSIGNED NOT NULL,
  text       VARCHAR(500) NOT NULL,
  status     ENUM('visible','hidden','deleted') NOT NULL DEFAULT 'visible',
  created_at DATETIME NOT NULL,
  KEY idx_comments_reel (reel_id, status, created_at),
  KEY idx_comments_user (user_id, created_at)
);

CREATE TABLE app_reports (
  id            CHAR(36) PRIMARY KEY,
  reporter_id   INT UNSIGNED NOT NULL,
  target_type   ENUM('reel','comment','user','message') NOT NULL,
  target_id     VARCHAR(100) NOT NULL,
  reason        VARCHAR(50) NOT NULL,
  details       VARCHAR(500) NOT NULL DEFAULT '',
  content_snapshot TEXT NULL,
  status        ENUM('open','reviewed','dismissed') NOT NULL DEFAULT 'open',
  created_at    DATETIME NOT NULL,
  UNIQUE KEY uq_report_once (reporter_id, target_type, target_id),
  KEY idx_reports_queue (status, created_at)
);
```

### 13.2 Upload contract

The main API never proxies the video body. It creates a pending row and a short-lived
signed ticket; the app uploads directly to z.com.

1. `POST /v1/reels/uploads` with required `Idempotency-Key`:

```json
{
  "caption": "optional, max 300",
  "fileName": "gallery-name.mp4",
  "sizeBytes": 12345678,
  "mimeType": "video/mp4",
  "sha256": "64 lowercase hex characters"
}
```

Validation: authenticated, MP4 only, 1 byte..50 MB, valid SHA-256, caption <=300, and
fewer than 5 reels created by this user in the last 24 hours. The API inserts a `pending`
reel and returns:

```json
{
  "ok": true,
  "reel": { "id": "uuid", "status": "pending" },
  "upload": {
    "url": "https://video.example.com/reels/upload.php",
    "token": "short-lived HS256 ticket",
    "expiresAt": "2026-11-25T12:15:00.000Z",
    "maxBytes": 52428800
  }
}
```

The ticket is signed with a **separate** `REEL_UPLOAD_SECRET`, contains `sub`, `reelId`,
`purpose = reel-upload`, expected SHA-256/size, `jti`, and a 15-minute expiry. It is not a
normal API access token and cannot call the main API.

2. The app sends multipart `video` to the z.com URL with
   `Authorization: Bearer <ticket>`. The uploader validates the ticket, size, MIME/magic
   bytes, and SHA-256; writes `<reelId>.mp4` using exclusive create; and returns
   `{ok, videoUrl, sha256, sizeBytes, durationMs?, posterUrl?}`.

3. `POST /v1/reels/{id}/complete`:

```json
{ "videoUrl": "https://.../media/<id>.mp4", "sha256": "...", "sizeBytes": 12345678 }
```

The API verifies ownership, pending state, configured public base URL, exact storage key,
hash, and size. It atomically changes `pending` → `visible`. Replaying the same completion
returns the existing reel; a different hash/size returns 409.

`DELETE /v1/reels/{id}` is an idempotent owner soft-delete. Admin deletion uses the admin
endpoint and requests best-effort physical deletion from z.com.

### 13.3 z.com hosting

Deployable folder: `ghosst-web/reels/` (FTP this folder to the z.com web root).

- `config.example.php` with placeholders for `REEL_UPLOAD_SECRET` and
  `REEL_PUBLIC_BASE_URL`; real `config.php` is gitignored.
- `upload.php`: stateless ticket verifier, `finfo`, MP4 `ftyp` check, streamed size cap,
  SHA-256, exclusive file creation, no database access.
- `delete.php`: admin-ticket-only deletion. Resolve the real path, require it below the
  media root and one level deep, and verify the filename is the ticket's reel ID.
- `media/.htaccess`: disable indexes/CGI/PHP handlers and serve only `.mp4` as
  `video/mp4` with `X-Content-Type-Options: nosniff`.
- If `ffprobe`/FFmpeg is available, capture duration and generate a poster. Otherwise the
  app uses a play-placeholder. Duration remains a target, not a hard v1 gate.
- The main API expires stale pending rows older than 24 hours and sends their reel IDs to
  z.com in a signed delete manifest. The z.com cleanup script deletes only IDs named in a
  valid admin-signed manifest; it never deletes media by age alone.

The Android app receives only the public HTTPS URL and upload ticket. It never receives
FTP credentials or the shared secret.

### 13.4 Feed and interaction API

- `GET /v1/reels?feed=for-you|following&limit=10&offset=0`
- `GET /v1/reels/{id}`
- `POST /v1/reels/{id}/likes` / `DELETE /v1/reels/{id}/likes`
- `GET /v1/reels/{id}/comments?limit=20&offset=0`
- `POST /v1/reels/{id}/comments` `{text: 1..500}`
- `DELETE /v1/reels/{id}/comments/{commentId}` — owner or moderator
- `POST /v1/reports` `{targetType, targetId, reason, details?, snapshot?}`

For `message` reports, the app includes the reported text in `snapshot` (required, max 500)
because moderators are intentionally not granted access to private Firestore threads. For
`user` reports, the moderator sees the target public profile and report details. Reel and
comment targets are resolved from MySQL. Message snapshots are untrusted display text and
must be HTML-escaped in the admin page.

All list endpoints paginate. Like/follow operations are idempotent. Comment writes are
limited to 30 per hour per user; reports to 20 per day and one per target.

Reel response shape:

```json
{
  "ok": true,
  "reels": [{
    "id": "uuid",
    "caption": "caption",
    "videoUrl": "https://...",
    "posterUrl": null,
    "durationMs": null,
    "createdAt": "2026-11-25T12:00:00.000Z",
    "creator": { "id": "42", "displayName": "Name", "avatarUrl": null, "isAdmin": false },
    "likeCount": 3,
    "commentCount": 1,
    "isLiked": false,
    "isFollowing": false,
    "isMine": false
  }],
  "nextOffset": 10
}
```

### 13.5 App UI and playback

- Add **Reels** as a bottom-nav destination after Chat; Admin remains last for admins.
- `ReelsScreen` has For You / Following segments and a vertical `PageView`.
- Add the official `video_player` dependency. Each visible reel owns a
  `VideoPlayerController.networkUrl`; initialize, loop, set volume 0, play, and dispose.
  Only the active page (and at most one preloaded neighbour) may play.
- Tap toggles play/pause; a speaker button toggles mute. A thin progress indicator and
  loading/error placeholder are always available.
- Right rail: creator avatar, like, comment, report. Bottom: creator handle, caption, and
  optional duration.
- Comments open a modal bottom sheet with paginated history and a composer.
- `ReelUploadScreen` uses the existing `file_picker` with `FileType.video`, validates
  extension/MIME/size, computes SHA-256 with the existing `crypto` dependency, shows upload
  progress, then completes the pending reel.
- `UserProfileScreen` shows a 3-column reel grid. Without a poster, show a branded
  play-placeholder rather than starting many video controllers.

### 13.6 Moderation

Add `ghosst-web/admin/reels.php`, linked from the existing admin sidebar:

- Queue of open reports and reels filtered by status.
- Video preview, creator, caption, counts, and report reason. Message reports show the
  submitted text snapshot; user reports link to the target public profile.
- Hide/show/delete reel; hide/restore comment; mark report reviewed/dismissed.
- Guard with `requireSocialModerator()`: website `role = 'admin'` OR app
  `users.is_admin = 1`/`users.is_moderator = 1`. Show the sidebar link only to those roles.
- Reuse the admin CSRF and action-log patterns from `admin/feedbacks.php`.
- Hiding a reel removes it from both feeds immediately. Physical file deletion is
  best-effort; failure is logged and does not block metadata deletion.

## 14. API and error conventions

- Existing envelope remains: `{ok: true, ...}` or
  `{ok: false, error: {code, message, requestId}}`.
- Plural resource paths, camelCase JSON fields, lowercase enum values.
- 400 malformed/invalid input, 401 unauthenticated, 403 forbidden, 404 not found,
  409 conflict/rate state, 413 upload too large, 429 rate limited, 503 feature not
  configured.
- Every protected route uses `required`; every admin route calls `require_admin()` or
  `require_moderator()` explicitly.
- Every SQL value is bound. User IDs are cast/validated before use.
- Upload-init honors `Idempotency-Key` with the existing atomic `idem_reserve()` pattern;
  same key/different payload is rejected.

## 15. Security and privacy

### 15.1 Threat model

| Threat | Control |
|---|---|
| Impersonated DM sender/participant | Firebase custom token + participant rules |
| Forged upload ticket | Separate HMAC secret, 15-minute expiry, bound reel/hash/size |
| Path traversal/script upload | Server-generated UUID filename, MIME + magic check, no PHP handlers in media dir |
| IDOR on profile/reel/comment | Ownership checks and safe field allowlists |
| SQL injection/XSS | PDO prepared statements; Flutter text widgets; admin HTML escaping |
| Storage/DB DoS | 50 MB cap, 5 uploads/day, pagination, comment/report limits |
| Fake admin action | Existing JWT role claims + admin route guard |
| PII disclosure | No email in public profile/Firestore DMs; private feedback hidden |
| Account deletion gaps | New stores enumerated and scrubbed; privacy pages updated |

### 15.2 Privacy edits

Update `docs/index.html`:

- Firestore now receives account ID and message text for **world chat and private
  messages**, plus display name for world chat.
- MySQL stores public profile fields, follows, reel metadata, likes/comments/reports, and
  private app feedback.
- z.com stores user-uploaded MP4 videos and optional posters.
- Add user-generated content and account ID to the Play Data Safety declarations.

Update `docs/delete-account.html`:

- Private conversations are deleted for both participants.
- Follows, likes, comments, reports, app feedback, avatar, and reel metadata are deleted.
- Uploaded video/poster files are deleted best-effort; operational/abuse-prevention
  tombstones may remain without profile PII.
- Keep the existing world-chat scrub wording.

## 16. Project structure

```text
lib/
  services/
    direct_chat_service.dart       # Firestore DMs/blocks
    models.dart                    # PublicUser, Reel, ReelComment, Feedback, Report
    worker_backend.dart            # all new HTTP methods
  screens/
    inbox_screen.dart
    direct_chat_screen.dart
    user_profile_screen.dart
    feedback_screen.dart
    reels_screen.dart
    reel_upload_screen.dart
    reel_comments_screen.dart
  main.dart                        # nav + profile entry points

ghosst-web/
  api/
    routes/
      users.php
      feedback.php
      follows.php
      reels.php
      reports.php
    lib/
      social.php
      reels.php
    tests/
      social_test.php
  database/
    mobile_app_social.sql
  admin/
    reels.php
  reels/
    .gitignore
    config.example.php
    upload.php
    delete.php
    cleanup.php
    media/.htaccess
    README.md

docs/
  superpowers/specs/2026-11-25-social-features-design.md
  index.html
  delete-account.html

test/
  direct_chat_service_test.dart
  social_models_test.dart
  user_profile_screen_test.dart
  feedback_screen_test.dart
  reels_screen_test.dart
  reel_upload_test.dart

firestore.rules                      # reviewed merge of existing + DM/block rules
```

## 17. Commands and verification

```powershell
flutter pub get
flutter analyze
flutter test
flutter test test/social_models_test.dart
flutter test test/reel_upload_test.dart
flutter test test/reels_screen_test.dart

# Local API from the repository root
php -S 127.0.0.1:8099 -t ghosst-web/api ghosst-web/api/index.php

# PHP syntax checks for changed files
php -l ghosst-web/api/routes/reels.php
php -l ghosst-web/reels/upload.php

# Pure PHP self-check (no live DB)
php ghosst-web/api/tests/social_test.php
```

### 17.1 Testing strategy

- **Pure Dart:** thread ID determinism, validators, JSON parsing/defaults, feed selection,
  SHA-256/size guard, pagination parsing.
- **Widget:** injected fake clients for inbox/profile/feedback/reels; no platform channels.
  Test empty/error/offline states, form validation, unread badge, follow button, like
  optimism/rollback, upload progress, and vertical page changes.
- **PHP:** ticket sign/verify/expiry/wrong-secret, MP4 magic validation, safe storage-key
  construction, caption/comment/report validators, pagination clamping.
- **Firestore rules (manual, two test accounts + outsider):** participant read/write;
  outsider denial; sender spoof denial; message edit denial; block prevents new messages;
  read marker can only advance own key.
- **z.com upload (manual):** missing/expired/wrong-purpose ticket; oversized file; MIME and
  hash mismatch; valid upload; replay cannot overwrite; media PHP does not execute.
- **Database/API (staging):** migration applies cleanly; idempotent follow/like/complete;
  rate limits; admin hide removes reel from feeds; account deletion removes social rows.

## 18. Rollout and owner setup

1. Implement each module on its own branch/slice.
2. **Private chat:** review and publish Firestore rules; verify world chat still works.
3. **Profiles/feedback/social graph:** apply `mobile_app_social.sql`, upload changed API
   files, then merge the app slice.
4. **Reels:** create z.com HTTPS endpoint, FTP `ghosst-web/reels/`, set a random
   `REEL_UPLOAD_SECRET` on both hosts, set `REEL_PUBLIC_BASE_URL` in the main API, apply
   SQL/API/admin files, then merge the app slice.
5. Test both flavors. Do not promote test-ad artifacts.
6. Update privacy/Data Safety disclosures before production release.

If z.com or the API is not configured, the Reels tab shows a clear unavailable state and
the rest of the app continues to work.

## 19. Known limits and shortcuts

- `shortcut: DM pacing is client-side only; add Firestore App Check or Cloud Functions
  pacing if spam appears.`
- `shortcut: reel duration is a 60-second target, not a hard gate unless ffprobe is
  installed; add server-side duration rejection when the hosting toolchain is confirmed.`
- Firestore Spark quota is assumed for DMs. Revisit pricing/quotas if DAU grows.
- No DM push notifications because the app currently stores no per-user FCM token.
- Reel files are public HTTPS URLs. Anyone with a URL can view it; there is no per-viewer
  authorization in v1.
- Account deletion's Firestore/z.com cleanup is best-effort and logged; MySQL cleanup is
  transactional.
- A website ban can leave an already-issued Firebase ID token usable for at most its
  remaining 1-hour lifetime. The app self-signs-out when `/me` rejects the account; immediate
  REST revocation would require Firebase account disabling/status sync.
- Admin moderation is post-publication, not pre-publication.

## 20. Resolved owner decision

The new checked-in `firestore.rules` is authoritative. It will combine the current
world-chat field contract used by `ChatService` (including `replyToId`) with the DM/block
rules in this document. The owner must review and publish it before the private-chat app
slice ships.

## 21. Success criteria

- [ ] Two signed-in users can exchange realtime DMs; an outsider cannot read them.
- [ ] Inbox unread clears on open and survives app restart.
- [ ] A public profile never exposes email, balance, purchases, or ban reason.
- [ ] Message and Follow actions work from a public profile.
- [ ] Private app feedback appears in the existing admin feedback page.
- [ ] Follow/unfollow is idempotent and counts are correct.
- [ ] A user can upload a valid MP4 <=50 MB and see it in For You.
- [ ] Vertical swipe plays one reel at a time, muted and looping.
- [ ] Like, comment, follow, report, and delete-own-reel work.
- [ ] Admin hide removes a reel from both feeds.
- [ ] Account deletion removes new MySQL social data and scrubs Firestore/z.com data.
- [ ] `flutter analyze` and `flutter test` pass; PHP changed files lint cleanly.
- [ ] Privacy policy, deletion page, and Play Data Safety declarations are updated.

## 22. Owner inputs required before the reels slice

- z.com HTTPS upload URL/domain.
- A random `REEL_UPLOAD_SECRET` stored only on the API host and z.com.
- Confirmation that z.com runs PHP 8 with `fileinfo` and `hash`.
- Optional: whether FFmpeg/ffprobe is available for duration and poster generation.
