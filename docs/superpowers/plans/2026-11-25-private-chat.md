# Private Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add realtime 1:1 text DMs between any signed-in users, with an inbox, unread state, blocking, and reporting.

**Architecture:** Reuse the existing Firebase custom-token session. Store threads/messages in Firestore under participant-scoped rules; use the PHP API only for safe user search, generic reports, and best-effort account-deletion cleanup.

**Tech Stack:** Flutter/Dart (`cloud_firestore`, `firebase_auth`), PHP 8/MySQL, Firestore Security Rules.

**Spec:** `docs/superpowers/specs/2026-11-25-social-features-design.md` (approved 2026-11-25), sections 8–9, 14–15, 17–19.

## Global Constraints

- Any signed-in user may DM any other signed-in user; follows are not required.
- DM text is trimmed, 1..500 characters; client cooldown is 2 seconds.
- No email, display name, coin balance, or purchase data is written to private Firestore messages.
- Network access stays in `lib/services/worker_backend.dart`; Firestore access stays in `lib/services/direct_chat_service.dart`.
- Tests use injected fakes and must not initialize Firebase or touch the network.
- `users.id` is a string in Dart/Firebase even though MySQL stores an integer.
- The new repo `firestore.rules` is authoritative but must be reviewed by the owner before publishing.
- Do not bump `pubspec.yaml` build number or push to `main`; CI owns releases.

## Review Focus

1. Outsider or forged participant reads/writes a thread → denied by rules; pinned in Task 1 rules contract and Task 6 manual matrix.
2. Empty/whitespace/>500-character DM or self-thread → rejected before any write; pinned in Task 2 tests.
3. Blocked user starts a new conversation → rules deny message create; pinned in Task 1 rules and Task 6 manual matrix.
4. Account deleted/banned while Firebase still has a session → app signs out when `/me` rejects; pinned in Task 3 tests and Task 6 manual check.
5. Firestore/API unavailable → inbox/chat show retry states without breaking world chat or other tabs; pinned in Task 5 fake-client tests.

---

### Task 1: Firestore rules, report schema, and safe user search

**Files:**
- Create: `firestore.rules`
- Create: `ghosst-web/database/mobile_app_social.sql`
- Create: `ghosst-web/api/lib/social.php`
- Create: `ghosst-web/api/routes/users.php`
- Create: `ghosst-web/api/routes/reports.php`
- Modify: `ghosst-web/api/index.php`
- Test: `ghosst-web/api/tests/social_test.php`

**Interfaces:**
- Consumes: existing `world_chat` rules contract from `docs/superpowers/specs/2026-11-07-world-chat-design.md`.
- Produces:
  - `social_public_user(array $row, array $viewer = []): array`
  - `social_user_by_id(string $id): ?array`
  - `users_search(array $ctx): array`
  - `reports_create(array $ctx): array`
  - SQL table `app_reports` for later reel moderation.

- [ ] **Step 1: Write the PHP validator tests**

Create `ghosst-web/api/tests/social_test.php` with assertions for: public user allowlist excludes email/balance/password; message report requires a 1..500 snapshot; reason is in the allowed enum; pagination clamps `limit` to 1..50 and rejects negative offset; user IDs must be positive integers.

Run: `php ghosst-web/api/tests/social_test.php`
Expected: FAIL because `social.php` does not exist.

- [ ] **Step 2: Create the migration and social helpers**

`mobile_app_social.sql` creates only `app_reports` in this slice, using `CREATE TABLE IF NOT EXISTS` so later slices can extend the same file. Implement `social_public_user()` with an explicit field allowlist and `social_user_by_id()` selecting only `id`, `username`, `display_name`, `avatar_url` when present, `created_at`, `is_admin`, `is_moderator`, `deleted_at`, and `is_banned`. Do not use `SELECT *`.

- [ ] **Step 3: Add user search and report routes**

`GET /v1/users/search?q=...&limit=20&offset=0` requires auth, minimum 2 characters, searches display name/username, and returns safe summaries. `POST /v1/reports` accepts `{targetType, targetId, reason, details?, snapshot?}`; `message` requires `snapshot`; all inputs are length/enum validated and parameterized. Register both routes as `required`.

- [ ] **Step 4: Write the authoritative Firestore rules**

Create `firestore.rules` with the current `world_chat` field contract (`uid`, `name`, `text`, `admin`, `ts`, optional `photoUrl`, `replyName`, `replyText`, and `replyToId`) plus `direct_threads`, nested `messages`, and `user_blocks` rules from spec section 9.2. Include comments identifying the world-chat block as preserved behavior. Do not add Anonymous Auth or open reads.

- [ ] **Step 5: Run checks and commit**

Run: `php ghosst-web/api/tests/social_test.php` → `ok`; `php -l` on all changed PHP files → no syntax errors.

```bash
git add firestore.rules ghosst-web/database/mobile_app_social.sql ghosst-web/api/lib/social.php ghosst-web/api/routes/users.php ghosst-web/api/routes/reports.php ghosst-web/api/index.php ghosst-web/api/tests/social_test.php
git commit -m "feat(social): secure DM rules, user search, and reports"
```

### Task 2: Direct-chat models and service

**Files:**
- Create: `lib/services/direct_chat_service.dart`
- Modify: `lib/services/models.dart`
- Create: `test/direct_chat_service_test.dart`
- Modify: `lib/services/worker_backend.dart`

**Interfaces:**
- Consumes: `Backend.currentUser()`, Firebase custom-token session, `Backend.searchUsers()`, `Backend.reportContent()`.
- Produces:
  - `class ChatUserSummary { String id, name; String? avatarUrl; factory ChatUserSummary.fromJson(...); }`
  - `class DirectThread`, `class DirectMessage`
  - `String directThreadId(String uidA, String uidB)`
  - `String? validateDirectMessage(String text)`
  - `abstract class DirectChatClient { Stream<List<DirectThread>> threads(); Stream<List<DirectMessage>> messages(String threadId); Future<String?> send(String threadId, String text); Future<void> markRead(String threadId); Future<bool> isBlocked(String uid); Future<void> block(String uid); Future<void> unblock(String uid); Future<bool> ensureSignedIn(); Future<void> signOut(); }`
  - `class DirectChatService implements DirectChatClient`

- [ ] **Step 1: Write failing pure-Dart tests**

Assert `directThreadId('2','10') == directThreadId('10','2')`, empty/self IDs throw or return a documented invalid result, `validateDirectMessage('')`, whitespace, and 501 chars return errors, 500 chars return null, and the 2-second cooldown helper rejects rapid sends.

Run: `flutter test test/direct_chat_service_test.dart`
Expected: FAIL because the service does not exist.

- [ ] **Step 2: Implement models, validation, and client contract**

Add `ChatUserSummary` to `models.dart`. Use immutable classes with `fromJson`/Firestore mapping for threads/messages. Define `threads()`, `messages(threadId)`, `send(threadId, text)`, `markRead(threadId)`, `isBlocked(uid)`, `block(uid)`, `unblock(uid)`, `ensureSignedIn()`, and `signOut()`. Keep all Firestore calls in this file.

- [ ] **Step 3: Implement `DirectChatService`**

Use deterministic thread IDs, `FieldValue.serverTimestamp()`, Firestore transactions for message + thread metadata, and participant arrays. `markRead()` updates only the current UID's `lastReadAt` entry. `ensureSignedIn()` reuses `ChatService`/`Backend.firebaseToken()` and signs out if `Backend.currentUser()` is null.

- [ ] **Step 4: Add backend methods**

Add `Backend.searchUsers(String query) → Future<List<ChatUserSummary>>` and `Backend.reportContent({required String targetType, required String targetId, required String reason, String details = '', String? snapshot}) → Future<void>` to `worker_backend.dart`.

- [ ] **Step 5: Run tests/analyze and commit**

Run: `flutter test test/direct_chat_service_test.dart` → pass; `flutter analyze` → no issues.

```bash
git add lib/services/models.dart lib/services/direct_chat_service.dart lib/services/worker_backend.dart test/direct_chat_service_test.dart
git commit -m "feat: realtime direct-chat service and validation"
```

### Task 3: Account-deletion cleanup and session revocation

**Files:**
- Modify: `ghosst-web/api/lib/firebase.php`
- Modify: `ghosst-web/api/routes/account.php`
- Modify: `lib/services/chat_service.dart`
- Test: `test/chat_service_test.dart`

**Interfaces:**
- Produces: `firebase_scrub_social(string $uid): void`, `firebase_delete_user(string $uid): void`.
- `ChatService.ensureSignedIn()` signs out Firebase when the backend has no live user.

- [ ] **Step 1: Add PHP structural tests**

Extend `social_test.php` with checks that social cleanup is guarded by `firebase_enabled()` and that deletion helpers never throw by contract (source-level assertions are acceptable for the no-network test).

- [ ] **Step 2: Implement social scrub and Auth deletion**

Add Identity Toolkit scoped OAuth support to `firebase.php`. `firebase_scrub_social()` queries `direct_threads` where `participants array-contains uid`, deletes message subcollections and thread docs in batches, then deletes owned block docs. `firebase_delete_user()` calls the Firebase Auth Admin delete endpoint. Both are best-effort, quota-aware, and log failures.

- [ ] **Step 3: Hook cleanup into `account_remove`**

After the MySQL commit and existing world-chat scrub, call `firebase_scrub_social($uid)` and `firebase_delete_user($uid)` when Firebase is enabled.

- [ ] **Step 4: Harden app session validation**

In `ChatService._ensureSignedInImpl()`, if `Backend.currentUser()` is null, sign out Firebase and return false. Add a pure/injected test proving a rejected backend session cannot leave `hasSession` true.

- [ ] **Step 5: Run checks and commit**

Run: `php ghosst-web/api/tests/social_test.php` → `ok`; `flutter test test/chat_service_test.dart test/direct_chat_service_test.dart` → pass; PHP lint clean.

```bash
git add ghosst-web/api/lib/firebase.php ghosst-web/api/routes/account.php ghosst-web/api/tests/social_test.php lib/services/chat_service.dart test/chat_service_test.dart
git commit -m "feat: revoke social data and Firebase session on account deletion"
```

### Task 4: Inbox screen and shell entry point

**Files:**
- Create: `lib/screens/inbox_screen.dart`
- Create: `test/direct_chat_inbox_test.dart`
- Modify: `lib/screens/chat_screen.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `DirectChatClient`, `DirectThread`, `Backend.searchUsers()`.
- Produces: `InboxScreen({DirectChatClient? client, VoidCallback? onOpenChat})`.

- [ ] **Step 1: Write failing widget tests**

Fake client streams two threads. Assert newest-first ordering, unread dot when `lastMessageAt > lastReadAt[myUid]`, no unread for own last message, empty state, and error/retry state. Assert ChatScreen shows an Inbox button.

- [ ] **Step 2: Implement `InboxScreen`**

Live thread list, participant public summaries, last message/time, unread indicator, New message search sheet, and retry. Use existing theme/premium primitives and 48dp touch targets.

- [ ] **Step 3: Wire ChatScreen and shell**

Add an Inbox button/badge to `ChatScreen`; open `InboxScreen` via `Navigator`. Sign out `DirectChatService` wherever `ChatService` is signed out.

- [ ] **Step 4: Run tests/analyze and commit**

Run: `flutter test test/direct_chat_inbox_test.dart test/chat_screen_test.dart` → pass; `flutter analyze` → no issues.

```bash
git add lib/screens/inbox_screen.dart lib/screens/chat_screen.dart lib/main.dart test/direct_chat_inbox_test.dart
git commit -m "feat: private-message inbox and chat entry point"
```

### Task 5: Direct-chat screen, block, and report

**Files:**
- Create: `lib/screens/direct_chat_screen.dart`
- Create: `test/direct_chat_screen_test.dart`

**Interfaces:**
- Consumes: `DirectChatClient`, `DirectMessage`, peer summary passed from the inbox/search.
- Produces: `DirectChatScreen({required String peerId, required String peerName, String? peerAvatarUrl, DirectChatClient? client})`.

- [ ] **Step 1: Write failing widget tests**

Assert messages render oldest-to-newest, own messages align right, empty input does not send, send failure restores draft, opening the thread calls `markRead`, Block calls `block(peerId)`, and Report calls `Backend.reportContent` through an injected callback.

- [ ] **Step 2: Implement the screen**

Reversed live list, composer, pending/offline indicator, peer header, block confirmation, and report bottom sheet. Message reports include the reported text snapshot. No client message edit/delete.

- [ ] **Step 3: Run tests/analyze and commit**

Run: `flutter test test/direct_chat_screen_test.dart` → pass; `flutter analyze` → no issues.

```bash
git add lib/screens/direct_chat_screen.dart test/direct_chat_screen_test.dart
git commit -m "feat: one-to-one chat screen with block and report"
```

### Task 6: Rules regression, docs, and full gates

**Files:**
- Modify: `docs/index.html`
- Modify: `docs/delete-account.html`
- Modify: `ghosst-web/api/README.md`

- [ ] **Step 1: Document Firestore deployment and deletion behavior**

Add the authoritative rules file, custom-token requirements, DM data model, block behavior, and deletion cleanup to `api/README.md`.

- [ ] **Step 2: Update privacy/deletion pages**

State that Firestore stores account ID and private message text; private conversations are deleted for both participants on account deletion. Keep the existing world-chat wording.

- [ ] **Step 3: Run full gates**

Run: `flutter analyze` → no issues; `flutter test` → all pass; `php ghosst-web/api/tests/social_test.php` → `ok`; PHP lint on all changed files.

- [ ] **Step 4: Manual rules matrix before merge**

Owner publishes `firestore.rules` to a staging Firebase project or reviews in console. Verify: world chat still works; participant can read/send; outsider denied; sender spoof denied; message edit denied; block denies new messages; read marker cannot change the peer's key.

- [ ] **Step 5: Commit**

```bash
git add docs/index.html docs/delete-account.html ghosst-web/api/README.md
git commit -m "docs: private chat privacy, deletion, and rules setup"
```
