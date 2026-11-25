# Public Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a safe public profile for every signed-in user, reachable from world chat and private chat, with avatar, identity, join date, social counts, Message, and Report actions.

**Architecture:** Store the Google avatar URL on the shared `users` row and expose an allowlisted PHP profile endpoint. The Flutter profile screen consumes that endpoint and opens the existing direct-chat thread. Forward social tables are created now so later follow/reel slices can populate the counts without another profile migration.

**Tech Stack:** Flutter/Dart, PHP 8/PDO MySQL, existing Dio API client.

**Spec:** `docs/superpowers/specs/2026-11-25-social-features-design.md` (approved 2026-11-25), sections 8, 10, 14–15, 17–19.

**Depends on:** `docs/superpowers/plans/2026-11-25-private-chat.md`.

## Global Constraints

- Public profile responses never include email, password, balance, coins, purchases, ban reason, or reset tokens.
- `users.id` remains an integer in SQL and a string in JSON.
- Avatar URLs must be HTTPS on `*.googleusercontent.com`; no arbitrary remote URL fetch.
- HTTP calls stay in `lib/services/worker_backend.dart`; models live in `lib/services/models.dart`.
- Tests use injected loaders/callbacks and no network.
- Do not manually bump the build number or push to `main`.

## Review Focus

1. Deleted/banned user profile → 404, no cached PII shown; pinned in Task 2 API tests.
2. Missing/blank display name or avatar → username/initials fallback, no broken image; pinned in Task 4 widget tests.
3. Malformed Google photo URL → ignored, existing avatar retained; pinned in Task 1 PHP tests.
4. Profile API down → retry state, chat navigation still works; pinned in Task 4 widget tests.
5. Own profile tap → existing account ProfileScreen, not a public profile loop; pinned in Task 5 navigation test.

---

### Task 1: Avatar migration and Google photo sync

**Files:**
- Modify: `ghosst-web/database/mobile_app_social.sql`
- Modify: `ghosst-web/api/routes/auth.php`
- Modify: `lib/services/worker_backend.dart`
- Test: `ghosst-web/api/tests/social_test.php`

**Interfaces:**
- Produces: `social_google_photo_url(?string $url): ?string`.
- `POST /v1/auth/google` accepts optional `photoUrl` and stores it on new/existing users.

- [ ] **Step 1: Write failing PHP tests**

Assert HTTPS Google-hosted URLs are accepted; HTTP, empty, non-Google hosts, credentials in URL, and URLs over 1000 chars are rejected. Assert existing avatar is retained when the new photo is invalid.

Run: `php ghosst-web/api/tests/social_test.php`
Expected: FAIL because the helper does not exist.

- [ ] **Step 2: Extend the migration**

Add `ALTER TABLE users ADD COLUMN avatar_url VARCHAR(1000) NULL` and the forward tables `app_follows`, `app_reels`, `app_reel_likes`, and `app_reel_comments` from spec section 13.1, all `IF NOT EXISTS` where supported.

- [ ] **Step 3: Sync Google photo server-side**

Implement `social_google_photo_url()` in `social.php`. Include `avatar_url` in `google_upsert_user()` selection/insert/update. Update the verified user's avatar only when the new URL passes validation.

- [ ] **Step 4: Send photoUrl from the app**

`GoogleAuthResult.photoUrl` already exists. Change `Backend.signInWithGoogle()` to post `{idToken, photoUrl}`; keep local secure-storage photo write for backward compatibility.

- [ ] **Step 5: Run checks and commit**

Run: `php ghosst-web/api/tests/social_test.php` → `ok`; PHP lint clean.

```bash
git add ghosst-web/database/mobile_app_social.sql ghosst-web/api/routes/auth.php ghosst-web/api/tests/social_test.php lib/services/worker_backend.dart
git commit -m "feat(profiles): store verified Google avatar URLs"
```

### Task 2: Public profile API

**Files:**
- Modify: `ghosst-web/api/lib/social.php`
- Modify: `ghosst-web/api/routes/users.php`
- Modify: `ghosst-web/api/index.php`
- Test: `ghosst-web/api/tests/social_test.php`

**Interfaces:**
- Produces:
  - `users_show(array $ctx): array`
  - `users_reels(array $ctx): array`
  - `social_profile_counts(string $userId): array`

- [ ] **Step 1: Write failing API-shape tests**

Assert `social_public_user()` output keys are exactly the allowlisted public fields; deleted/banned rows are rejected; follower/following/reel counts default to zero; `limit` clamps to 1..50; unknown IDs map to 404.

- [ ] **Step 2: Implement profile queries**

`users_show()` validates a positive integer ID, loads the safe user row, computes counts from `app_follows`/`app_reels`, and adds viewer-relative `isFollowing` and `isSelf`. `users_reels()` returns only `visible` reels for that user; it returns an empty list until the reels slice publishes content.

- [ ] **Step 3: Register routes**

Add authenticated `GET /v1/users/{id}` and `GET /v1/users/{id}/reels`; keep the existing search route unchanged.

- [ ] **Step 4: Run checks and commit**

Run: `php ghosst-web/api/tests/social_test.php` → `ok`; PHP lint clean. Smoke unauthenticated requests and expect 401, not 404.

```bash
git add ghosst-web/api/lib/social.php ghosst-web/api/routes/users.php ghosst-web/api/index.php ghosst-web/api/tests/social_test.php
git commit -m "feat(api): safe public user profiles and counts"
```

### Task 3: PublicUser model and backend methods

**Files:**
- Modify: `lib/services/models.dart`
- Modify: `lib/services/worker_backend.dart`
- Create: `test/social_models_test.dart`

**Interfaces:**
- Produces:
  - `class PublicUser { String id, displayName, username, createdAt; String? avatarUrl; bool isAdmin, isModerator, isFollowing, isSelf; int followerCount, followingCount, reelCount; factory PublicUser.fromJson(...); }`
  - `Backend.publicUser(String id) → Future<PublicUser>`

- [ ] **Step 1: Write failing model tests**

Parse a complete profile, missing optional fields, numeric/string ID, and malformed counts. Assert no JSON field named email/balance/password is accepted into the model.

Run: `flutter test test/social_models_test.dart`
Expected: FAIL because `PublicUser` is not defined.

- [ ] **Step 2: Implement `PublicUser` and `Backend.publicUser()`**

Use the existing model style and safe defaults. Keep viewer-relative flags explicit.

- [ ] **Step 3: Run tests/analyze and commit**

Run: `flutter test test/social_models_test.dart` → pass; `flutter analyze` → no issues.

```bash
git add lib/services/models.dart lib/services/worker_backend.dart test/social_models_test.dart
git commit -m "feat: public profile model and API client"
```

### Task 4: UserProfileScreen

**Files:**
- Create: `lib/screens/user_profile_screen.dart`
- Create: `test/user_profile_screen_test.dart`

**Interfaces:**
- Consumes: `PublicUser`, injected `Future<PublicUser> Function(String id)` loader, `Future<bool> Function(String id)? loadBlocked`, `VoidCallback onMessage`, `VoidCallback onReport`, `VoidCallback? onBlock`, `VoidCallback? onUnblock`.
- Produces: `UserProfileScreen({required String userId, String? initialName, loader, loadBlocked, onMessage, onReport, onBlock, onUnblock})`.

- [ ] **Step 1: Write failing widget tests**

Assert avatar/initials, display name/username fallback, admin/moderator badge, member-since text, three stats, Message callback, Report callback, Block/Unblock state and callbacks, loading state, error/retry state, and 48dp touch targets.

- [ ] **Step 2: Implement the profile screen**

Use `AppTheme`, `CardFrame`/`GlowCard`, and existing avatar patterns. Show a "Reels" section with an empty state in this slice; the reels plan replaces it with the grid. Report and Block/Unblock live in the overflow menu. Do not add Follow yet; the social-graph plan owns that button.

- [ ] **Step 3: Run tests/analyze and commit**

Run: `flutter test test/user_profile_screen_test.dart` → pass; `flutter analyze` → no issues.

```bash
git add lib/screens/user_profile_screen.dart test/user_profile_screen_test.dart
git commit -m "feat: public user profile screen"
```

### Task 5: Navigation wiring

**Files:**
- Modify: `lib/screens/chat_screen.dart`
- Modify: `lib/screens/direct_chat_screen.dart`
- Modify: `lib/main.dart`
- Test: `test/chat_screen_test.dart`, `test/direct_chat_screen_test.dart`, `test/user_profile_screen_test.dart`

**Interfaces:**
- `ChatScreen` and `DirectChatScreen` gain optional `ValueChanged<String>? onOpenProfile`.

- [ ] **Step 1: Write failing navigation tests**

Tapping another user's avatar/name calls `onOpenProfile(uid)`. Tapping own avatar does nothing or opens the account profile through the shell. The public profile Message button opens `DirectChatScreen` with the deterministic peer ID.

- [ ] **Step 2: Wire callbacks**

Add `onOpenProfile` to both chat screens. In `HomeShell`, push `UserProfileScreen`; its Message action pushes `DirectChatScreen`. Pass `DirectChatService.isBlocked/block/unblock` for the profile overflow actions. Own profile header continues to open the existing `ProfileScreen`.

- [ ] **Step 3: Run tests/analyze and commit**

Run targeted tests → pass; `flutter analyze` → no issues.

```bash
git add lib/screens/chat_screen.dart lib/screens/direct_chat_screen.dart lib/main.dart test/chat_screen_test.dart test/direct_chat_screen_test.dart test/user_profile_screen_test.dart
git commit -m "feat: open public profiles from chats"
```

### Task 6: Avatar deletion, privacy copy, and full gates

**Files:**
- Modify: `ghosst-web/api/routes/account.php`
- Modify: `docs/index.html`
- Modify: `SETUP.md`
- Test: `ghosst-web/api/tests/social_test.php`

- [ ] **Step 1: Blank avatar on account deletion**

In the existing `account_remove` transaction, set `avatar_url = NULL` with the other anonymized user fields. Add a source-level test that the update includes `avatar_url`.

- [ ] **Step 2: Update privacy/setup docs**

Document public profile fields, Google avatar storage, MySQL social tables, and the migration command. Do not claim public profiles expose email or purchase data.

- [ ] **Step 3: Run full gates**

Run: `flutter analyze` → no issues; `flutter test` → all pass; `php ghosst-web/api/tests/social_test.php` → `ok`; PHP lint clean.

- [ ] **Step 4: Commit**

```bash
git add ghosst-web/api/routes/account.php ghosst-web/api/tests/social_test.php docs/index.html SETUP.md
git commit -m "docs: public profile data and migration setup"
```
