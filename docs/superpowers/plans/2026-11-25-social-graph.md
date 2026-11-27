# Follows and Social Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add idempotent user follow/unfollow plus follower/following lists and counts on public profiles.

**Architecture:** Store edges in MySQL `app_follows`; expose authenticated plural-resource endpoints; add a Follow button to `UserProfileScreen` and simple paginated follower/following screens.

**Tech Stack:** PHP 8/PDO MySQL, Flutter/Dart, existing Dio client.

**Spec:** `docs/superpowers/specs/2026-11-25-social-features-design.md` (approved 2026-11-25), sections 10, 12, 14–15, 17–19.

**Depends on:** `docs/superpowers/plans/2026-11-25-public-profiles.md`.

## Global Constraints

- No self-follow; following is not required to send a DM.
- Follow/unfollow must be idempotent under retries and concurrent requests.
- Lists require authentication and paginate with `limit` 1..50, `offset` >=0.
- HTTP calls stay in `lib/services/worker_backend.dart`; models live in `lib/services/models.dart`.
- Tests use pure validators/injected clients and no MySQL/network.
- Do not manually bump the build number or push to `main`.

## Review Focus

1. Double-tap or retried follow/unfollow → one edge/no edge, correct count; pinned in Task 1 SQL/idempotency tests.
2. Self-follow or invalid user ID → 400/404, no edge; pinned in Task 1 tests.
3. Deleted/banned target → 404 and no follow edge; pinned in Task 1 tests.
4. Large follower list → bounded pagination, no unbounded query; pinned in Task 1 and Task 4 tests.
5. Follow API fails → button rolls back and shows Retry, no false count; pinned in Task 3 widget tests.

---

### Task 1: Follow API

**Files:**
- Create: `ghosst-web/api/routes/follows.php`
- Modify: `ghosst-web/api/index.php`
- Modify: `ghosst-web/api/lib/social.php`
- Test: `ghosst-web/api/tests/social_test.php`

**Interfaces:**
- Produces:
  - `follows_add(array $ctx): array`
  - `follows_remove(array $ctx): array`
  - `follows_list(array $ctx, string $direction): array`
  - `social_require_target_user(string $id): array`

- [ ] **Step 1: Write failing tests**

Assert positive-integer IDs, self-follow rejection, missing/deleted/banned target rejection, `limit` clamp, negative offset rejection, and response shape `{ok,isFollowing,followerCount}`.

Run: `php ghosst-web/api/tests/social_test.php`
Expected: FAIL because the handlers do not exist.

- [ ] **Step 2: Implement idempotent mutations**

`POST /v1/users/{id}/follow` uses `INSERT IGNORE`; `DELETE /v1/users/{id}/follow` deletes the edge. Both validate the target and return the current state/count. Do not rely on affected-row count for success.

- [ ] **Step 3: Implement lists**

`GET /v1/users/{id}/followers` and `/following` join safe public user fields, order by `created_at DESC, id DESC`, and return `{ok, users, nextOffset}`.

- [ ] **Step 4: Register routes and commit**

Run: `php ghosst-web/api/tests/social_test.php` → `ok`; PHP lint clean; unauthenticated smoke returns 401.

```bash
git add ghosst-web/api/routes/follows.php ghosst-web/api/index.php ghosst-web/api/lib/social.php ghosst-web/api/tests/social_test.php
git commit -m "feat(api): idempotent follows and social lists"
```

### Task 2: Backend client methods

**Files:**
- Modify: `lib/services/models.dart`
- Modify: `lib/services/worker_backend.dart`
- Test: `test/social_models_test.dart`

**Interfaces:**
- Produces:
  - `class FollowState { bool isFollowing; int followerCount; factory FollowState.fromJson(...); }`
  - `Backend.followUser(String id) → Future<FollowState>`
  - `Backend.unfollowUser(String id) → Future<FollowState>`
  - `Backend.followers(String id, {int limit=20, int offset=0}) → Future<List<PublicUser>>`
  - `Backend.following(String id, {int limit=20, int offset=0}) → Future<List<PublicUser>>`

- [ ] **Step 1: Write failing parsing tests**

Assert `FollowState.fromJson` parses boolean/numeric/string counts, defaults missing fields, and malformed list entries are skipped by the existing `PublicUser` list mapping pattern.

- [ ] **Step 2: Implement model and methods**

Add `FollowState` to `models.dart`. Call the Task 1 routes and map `PublicUser.fromJson`. Propagate `ApiException` so UI can roll back.

- [ ] **Step 3: Run tests/analyze and commit**

Run: `flutter test test/social_models_test.dart` → pass; `flutter analyze` → no issues.

```bash
git add lib/services/models.dart lib/services/worker_backend.dart test/social_models_test.dart
git commit -m "feat: follow API client methods"
```

### Task 3: Follow button on public profiles

**Files:**
- Modify: `lib/screens/user_profile_screen.dart`
- Modify: `test/user_profile_screen_test.dart`

**Interfaces:**
- `UserProfileScreen` gains `Future<FollowState> Function(String id)? onFollow` and `onUnfollow`.

- [ ] **Step 1: Write failing widget tests**

Assert Follow/Following label, hidden button for self, optimistic state, count update, API failure rollback, and disabled state while in flight.

- [ ] **Step 2: Implement the button**

Place beside Message. Use local optimistic state but restore the previous state/count on error and show a SnackBar with Retry.

- [ ] **Step 3: Wire default callbacks in `HomeShell`**

Pass `Backend.followUser`/`Backend.unfollowUser` when opening another user's profile.

- [ ] **Step 4: Run tests/analyze and commit**

Run targeted tests → pass; `flutter analyze` → no issues.

```bash
git add lib/screens/user_profile_screen.dart lib/main.dart test/user_profile_screen_test.dart
git commit -m "feat: follow and unfollow from public profiles"
```

### Task 4: Followers and Following screens

**Files:**
- Create: `lib/screens/social_list_screen.dart`
- Create: `test/social_list_screen_test.dart`

**Interfaces:**
- Produces: `enum SocialListDirection { followers, following }` and `SocialListScreen({required String userId, required SocialListDirection direction, Future<List<PublicUser>> Function(int offset)? load, ValueChanged<String>? onOpenProfile})`.

- [ ] **Step 1: Write failing widget tests**

Assert title, list rows, avatar/name fallbacks, tap callback, pagination trigger, empty state, and error/retry state.

- [ ] **Step 2: Implement the screen**

Infinite-scroll list with a 20-item page size and duplicate-ID filtering. Tapping a row pushes another public profile.

- [ ] **Step 3: Make profile stats tappable**

Followers and Following stat cells open `SocialListScreen` with the correct direction.

- [ ] **Step 4: Run tests/analyze and commit**

Run: `flutter test test/social_list_screen_test.dart test/user_profile_screen_test.dart` → pass; `flutter analyze` → no issues.

```bash
git add lib/screens/social_list_screen.dart lib/screens/user_profile_screen.dart test/social_list_screen_test.dart test/user_profile_screen_test.dart
git commit -m "feat: followers and following lists"
```

### Task 5: Full gates

- [ ] **Step 1: Run all checks**

Run: `flutter analyze` → no issues; `flutter test` → all pass; `php ghosst-web/api/tests/social_test.php` → `ok`; PHP lint clean.

- [ ] **Step 2: Manual API checks after deploy**

Verify follow → count 1; repeat follow → still 1; unfollow → 0; repeat unfollow → still 0; self-follow rejected; lists paginate.
