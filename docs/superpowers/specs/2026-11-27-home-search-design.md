# Home search for users and reels — design

**Date:** 2026-11-27
**Status:** awaiting approval

## Intent / why

From the Home tab, users should be able to find people and reels without
leaving the app. The search result must open the right destination directly:
a user → their profile, a reel → the reel view.

## Goals

1. Search icon in the Home (ReelsScreen) top bar that opens a full-screen
   Search page.
2. Typing at least 2 characters searches **users** and **reels** and shows two
   labelled sections with loading, empty, and error states.
3. Tapping a user opens their profile; tapping a reel opens that reel.
4. Reel results include counts and viewer flags, so they behave like feed reels.

## Non-goals / anti-goals

- No search of comments, products, tutorials, announcements, or messages.
- No hashtags/trending, no recent-search history, no server-side typo tolerance.
- No new dependency, no push/notification work, no website changes.
- No infinite scroll in v1 — first 20 users and 20 reels (API supports offset
  for a later pass).

## Constraints

- Home is the embedded `ReelsScreen` in `HomeShell`; the standalone ReelsScreen
  opened from profile/activity should not grow a search button.
- `GET /v1/users/search?q=` already exists and maps to `ChatUserSummary` via
  `Backend.searchUsers()` — reuse it, do not duplicate.
- No reel search endpoint exists; add one in the reel API group using the same
  `reel_social_map()` used by the feed/profile so counts/flags are present.
- API files are gitignored and uploaded manually to Hostinger; Dart changes are
  committed. All user-facing values escaped; search query bound as a LIKE param.
- Minimum query length 2 chars, matching the existing user search.

## Approaches

Chosen: **reuse `/v1/users/search` + add `/v1/reels/search`**, with one app
Search page calling both. Smallest backend addition, reuses the existing safe
user mapping, and keeps reel mapping in one place.

Rejected: one combined `/v1/search` endpoint (one call but duplicates user
mapping in PHP); client-side filtering of the loaded feed (no new API, but only
finds reels already on screen — not a real search).

## Design

### 1. API — reel search

- New `GET /v1/reels/search?q=&limit=&offset=` route in `api/index.php`, handler
  `reels_search()` in `api/routes/reel_social.php`, auth `required`.
- If `mb_strlen(q) < 2`: return `{ok:true, reels:[], nextOffset:0}`.
- Query: `app_reels r JOIN users u`, `r.status='visible'`, visible media exists,
  `u.deleted_at IS NULL AND u.is_banned = 0`, `r.caption LIKE ?` with `%q%`.
  Select the same count/flag columns as `reels_feed` and call
  `reel_social_map($row, $viewerId, $mediaMap)` for each row. Order by
  `r.created_at DESC, r.id DESC`; `social_pagination` cap 50 (default 20).
- Response: `{ok, reels, nextOffset}`.

### 2. Backend Dart surface

- `Backend.searchReels(String query, {int limit = 20, int offset = 0})` →
  `Future<List<Reel>>` via `GET /reels/search`, mapping `res['reels']`.
- Keep `Backend.searchUsers()` unchanged.

### 3. Search page — `lib/screens/search_screen.dart`

- New `SearchScreen` with optional injectable `searchUsers` and `searchReels`
  callbacks (defaults to `Backend`), plus `onOpenProfile` and `onOpenReel`.
- AppBar with back button and a `TextField` (autofocus, clear button).
- Debounce 350 ms; ignore queries shorter than 2 chars; reset results to empty.
- Body: loading indicator while a call is in flight; **each section owns its
  error/retry state** so a failed reel search does not hide successful user
  results (and vice versa):
  - `PEOPLE` — avatar, name, `@username`, tap → `onOpenProfile(id)`.
  - `REELS` — poster thumbnail (CachedNetworkImage), caption (1–2 lines),
    compact like/comment counts, tap → `onOpenReel(reel)`.
  - A section with zero results shows a small "No users found" / "No reels
    found" line; both empty shows a calm empty state.
- Keys: `search-input`, `search-clear`, `search-loading`, `search-user-<id>`,
  `search-reel-<id>`, `search-no-users`, `search-no-reels`,
  `search-users-error` / `search-reels-error`, `search-users-retry` /
  `search-reels-retry`.

### 4. Home entry point

- `ReelsScreen` gains optional `onOpenSearch` (VoidCallback). In the embedded
  top bar, add a search `IconButton` (tooltip 'Search', key `reels-search`)
  before the tabs; tapping calls the callback. Standalone ReelsScreen hides it.
- `SearchScreen` **pops itself before invoking either tap callback**, so
  tapping yourself switches the HomeShell tab (instead of appearing to do
  nothing) and Back never returns to stale results.
- `main.dart` wires `onOpenSearch` on the home ReelsScreen only.
  For reel results, fetch the exact reel with `Backend.reel(reel.id)` and open
  it through `_openCreatorReel`; extend that method's `load` closure so the
  requested id is **always prepended when missing from the first feed page**
  (today it only appends creator reels, which can open the wrong older reel).
  This also hardens the Activity route that already uses `_openCreatorReel`.

### 5. Tests / verification

- PHP self-check in `ghosst-web/api/tests/social_test.php`: short query returns
  no rows; visible reel with matching caption maps counts/flags; hidden reel,
  missing media, and banned creator are excluded; route registered in
  `index.php`.
- Flutter `test/search_screen_test.dart`: injected fakes prove 2-char gate,
  results render in both sections, user/reel taps dispatch the right callbacks,
  error state retries, and both-empty state. Add a `test/reels_screen_test.dart`
  case that the search button exists when `onOpenSearch` is supplied and is
  absent otherwise.
- Run PHP self-checks, `flutter test` (full), `flutter analyze`. No Flutter
  changes require the website upload, but the reel endpoint does.

### 6. Rollout

1. Upload `api/` (new route + handler) to Hostinger.
2. Ship the Flutter build with the search entry point.

## Reviewer decisions folded in

- Tapping a reel opens the **exact** reel: fetch by id and pin it, never rely on
  it being in the first feed page. Also fixes the Activity route's similar gap.
- SearchScreen pops itself before calling `onOpenProfile`/`onOpenReel`.
- Users and Reels sections fail independently; a partial outage still shows the
  successful section, each with its own Retry.

## Left to the builder

Exact section header styling, thumbnail size, and error copy are builder calls.
No product choice remains open.
