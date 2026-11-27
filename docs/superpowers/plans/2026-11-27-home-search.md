# Home Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Home search entry point that finds users and reels and opens the exact tapped result.

**Architecture:** Reuse `GET /v1/users/search`; add `GET /v1/reels/search` mapped through `reel_social_map`. A new SearchScreen calls both with independent error states. ReelsScreen gains a search button; main wires it and pins an exact reel by id when opening a result.

**Tech Stack:** Flutter/Dart records + `cached_network_image`, PHP 8 API, plain-PHP self-checks, Flutter widget tests.

**Spec:** `docs/superpowers/specs/2026-11-27-home-search-design.md`

## Global Constraints

- Minimum query length 2 characters; bound the query with LIKE params.
- User results use existing `/v1/users/search` + `ChatUserSummary`; do not add a second user mapping.
- Reel results must carry `likeCount`, `commentCount`, `isLiked`, `isFollowing`, `isMine` via `reel_social_map`.
- First 20 results per section; API supports offset but UI has no infinite scroll in v1.
- SearchScreen pops itself before invoking `onOpenProfile` / `onOpenReel`.
- Users/Reels sections own separate error+retry states; one failure must not hide the other.
- Tapping a reel opens the **exact** reel id, never an unrelated first-page reel.
- Website/API files are gitignored and uploaded manually; those tasks end with verification, not a git commit.

## Review Focus

1. Short queries return nothing — Task 1: `short query returns no reels`.
2. Hidden/banned/no-media reels are excluded — Task 1: `search excludes ineligible reels`.
3. Reel results carry counts and viewer flags — Task 1: `search results carry counts and flags`.
4. Partial failure keeps the successful section — Task 3: `failed reel search keeps user results`.
5. Exact reel is pinned when absent from first page — Task 4: `missing selected reel is fetched by id`.

---

### Task 1: Reel search endpoint

**Files:**
- Modify: `ghosst-web/api/index.php` (reel routes near line 132)
- Modify: `ghosst-web/api/routes/reel_social.php` (new `reels_search()`)
- Test: `ghosst-web/api/tests/social_test.php`

**Interfaces:**
- Consumes: `social_pagination()`, `reel_visible_media_map()`, `reel_social_map()`, `social_avatar_select()`.
- Produces: `GET /v1/reels/search?q=&limit=&offset=` → `{ok, reels, nextOffset}` with `Reel`-shaped JSON.

- [ ] **Step 1: Write the failing tests**

In `social_test.php`, set `$GLOBALS['social_reel_rows']` to one visible reel with `caption => 'hello search'`, `user_id => 42`, `like_count => 5`, `comment_count => 2`, `is_liked => 1`, `is_following => 1`, and media in `$GLOBALS['social_reel_media_rows']`. Add:
  - `search results carry counts and flags`: `reels_search(['query'=>['q'=>'hello'], 'user'=>['id'=>'42']])` returns one reel with those values.
  - `short query returns no reels`: `q => 'a'` returns empty `reels` and no DB query.
  - `search excludes ineligible reels`: assert the SQL in `$GLOBALS['social_queries']` contains `r.status = 'visible'`, `visible_media.status`, `u.deleted_at IS NULL AND u.is_banned = 0`, and `r.caption LIKE ?`.
  - `index.php` contains the route `'reels_search'`.

- [ ] **Step 2: Run it to verify it fails**

Run from `ghosst-web/api`: `php tests/social_test.php`
Expected: FAIL (handler missing).

- [ ] **Step 3: Implement `reels_search(array $ctx): array`**

Return early for `mb_strlen($q) < 2`; otherwise build the same SELECT as `reels_feed` (counts, flags, creator fields), add `r.caption LIKE ?`, visible reel/media/user predicates, `ORDER BY r.created_at DESC, r.id DESC`, `LIMIT/OFFSET` from `social_pagination`, bind `[$like, $viewerId, $viewerId]`, and map with `reel_social_map($row, $viewerId, $mediaMap)`. Register the route as `required`.

- [ ] **Step 4: Run it to verify it passes**

Run: `php tests/social_test.php`
Expected: PASS with all original assertions green.

- [ ] **Step 5: Verify, do not commit**

No tracked files changed (`ghosst-web/` is gitignored).

---

### Task 2: Backend search method

**Files:**
- Modify: `lib/services/worker_backend.dart` (next to `searchUsers`, ~line 420)
- Commit: yes.

**Interfaces:**
- Consumes: `/reels/search` JSON from Task 1.
- Produces: `Backend.searchReels(String query, {int limit = 20, int offset = 0}) → Future<List<Reel>>`.

- [ ] **Step 1: Write the failing test**

In `test/social_models_test.dart`, add `test('Backend exposes reel search', () { expect(Backend.searchReels, isA<Function>()); })` and import `worker_backend.dart`. The test cannot compile until the method exists — that is the RED.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/social_models_test.dart`
Expected: FAIL with "The getter 'searchReels' isn't defined for the type 'Backend'".

- [ ] **Step 3: Add the method**

`static Future<List<Reel>> searchReels(String query, {int limit = 20, int offset = 0})` → GET `/reels/search` with query `{'q': query, 'limit': '$limit', 'offset': '$offset'}`, mapping `(res['reels'] as List? ?? const [])` through `Reel.fromJson`.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/social_models_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/worker_backend.dart test/social_models_test.dart
git commit -m "feat: backend reel search method"
```

---

### Task 3: SearchScreen

**Files:**
- Create: `lib/screens/search_screen.dart`
- Create: `test/search_screen_test.dart`

**Interfaces:**
- Consumes: `ChatUserSummary`, `Reel`, `Backend.searchUsers`, `Backend.searchReels`.
- Produces: `SearchScreen({Key? key, Future<List<ChatUserSummary>> Function(String)? searchUsers, Future<List<Reel>> Function(String)? searchReels, ValueChanged<String>? onOpenProfile, ValueChanged<Reel>? onOpenReel})`; keys from spec.

- [ ] **Step 1: Write the failing tests**

In `test/search_screen_test.dart`, pump `SearchScreen` with injected fakes. Assert:
  - 1-char query performs no search (`search-no-users`, `search-no-reels` shown, calls == 0).
  - 2+ char query renders a user row and a reel row with their keys.
  - `failed reel search keeps user results`: reel fake throws, user fake succeeds → user row present, `search-reels-error` present, tap `search-reels-retry` re-runs only the reel fake.
  - tapping a user/reel pops the screen and dispatches the right callback (assert callback received exact tapped id/reel).

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/search_screen_test.dart`
Expected: FAIL (screen does not exist).

- [ ] **Step 3: Implement the screen**

Build AppBar + TextField (`search-input`, clear button `search-clear`), 350 ms debounce, ignore <2 chars. Run both injected searches concurrently; each section has its own loading/error/retry and empty state; render `GlowCard` rows for users (avatar, name, @username) and reels (poster, caption, compact counts). `Navigator.pop(context)` before each callback.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/search_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/search_screen.dart test/search_screen_test.dart
git commit -m "feat: search page for users and reels"
```

---

### Task 4: Home entry point and exact-reel pinning

**Files:**
- Modify: `lib/screens/reels_screen.dart` (`onOpenSearch`, `loadReel`, top bar)
- Modify: `lib/main.dart` (wire `onOpenSearch` and `loadReel`, import SearchScreen)
- Modify: `test/reels_screen_test.dart`
- Commit: yes.

**Interfaces:**
- Consumes: `SearchScreen` from Task 3, `Backend.reel` (existing), `Backend.searchReels` from Task 2.
- Produces: `ReelsScreen.onOpenSearch` (VoidCallback?), `ReelsScreen.loadReel` (`Future<Reel> Function(String)?`); key `reels-search`.

- [ ] **Step 1: Write the failing tests**

In `reels_screen_test.dart`, add:
  - `reels search button appears only when wired`: with `onOpenSearch` supplied, `find.byKey(const ValueKey('reels-search'))` finds one and tapping calls the callback; without it, finds nothing.
  - `missing selected reel is fetched by id`: `initialReelId: 'selected'`, injected `load` returns only `r1`, injected `loadReel` returns the selected reel; expect `Caption selected` visible.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/reels_screen_test.dart`
Expected: FAIL on the new tests (params do not exist).

- [ ] **Step 3: Wire the entry and the pin**

Add the two optional fields to `ReelsScreen`; add a search `IconButton` (tooltip 'Search', key `reels-search`) in the embedded top bar only, calling `onOpenSearch`. In `_load`, when `initialReelId` is present but absent from the loaded page, call `loadReel ?? Backend.reel` and prepend the result (best-effort try/catch) instead of relying only on creator reels. In `main.dart`, pass `onOpenSearch` on the home ReelsScreen to push `SearchScreen(onOpenProfile: _openUserProfile, onOpenReel: ...)`; the reel callback fetches `Backend.reel(reel.id)` and calls `_openCreatorReel`; pass `loadReel: Backend.reel` to the home ReelsScreen.

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/reels_screen_test.dart test/home_shell_navigation_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit and final gates**

```bash
git add lib/screens/reels_screen.dart lib/main.dart test/reels_screen_test.dart
git commit -m "feat: home search entry and exact reel result"
```
Then run all PHP self-checks from `ghosst-web/api`, full `flutter test`, and `flutter analyze`. Upload `api/` to Hostinger; ship the Flutter build.
