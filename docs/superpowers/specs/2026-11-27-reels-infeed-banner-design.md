# In-feed banner ads in the reels feed

Date: 2026-11-27
Size: small change (one screen + one small test file)

## Intent / why

Add passive ad revenue to the busiest screen. The reels (home) feed is the only
tab where the existing shell banner is deliberately hidden
(`showShellBanners = tab != SocialTab.home` in `lib/main.dart`), so it currently
shows no ads at all. The user chose recurring in-feed banners: after every 5th
post, each with its own load/dispose lifecycle. Ads stay passive — no coins,
no reward contract, no backend changes.

## Goals

- Show a banner card after every 5th reel post, both in the embedded home feed
  and in the pushed creator-reel screen (same `ReelsScreen` widget).
- Each ad slot manages its own `BannerAd` and disposes it when scrolled away or
  when the screen closes.
- Keep all 78 existing tests green without platform-channel mocks.

## Non-goals / anti-goals

- No changes to rewarded ads, coin balances, SSV, or the PHP API.
- No ad in Tutorials / Feedback sections (they are not reel posts).
- No change to the shell banner on the other tabs; no double banner on reels.
- No settings toggle or frequency control in the UI.

## Constraints / decisions made here

- Gate on `AdService.adsEnabled` AND `widget.active`. In widget tests the flag
  defaults to false, so no `AdWidget` is built and no channel call is made.
- Use `AdUnits.banner` at fixed `AdSize.banner` (320×50) inside a dark padded
  card. Inline adaptive is deliberately skipped for v1: fixed size needs no
  async sizing and keeps the list deterministic. Upgrade later if eCPM matters.
- Failed slots show nothing; no per-slot retry timers (N slots would mean N
  timers). A later feed rebuild gets a fresh attempt. Log via
  `AdService.logAdError` as the other ad code does.
- One parent listener on `AdService.adsEnabledNotifier` (not one per slot);
  it rebuilds the item layout when consent flips.
- One `ReelsScreen` builds the slot widget for all reels surfaces; no separate
  flag for the pushed screen.

## Approaches considered

- **A — parent-owned single ad:** smallest diff, one ad per feed session, reload
  on section switch. Rejected: user asked for a recurring slot in the feed.
- **B — self-contained slot at one fixed index:** clean encapsulation, but only
  one impression opportunity per session. Rejected in favour of C.
- **C — self-contained slot after every 5th post (chosen):** best revenue with
  each slot's lifecycle isolated. Cost: more ad requests and more live ad
  objects, bounded by how much of the feed is on screen. `ListView.separated`
  destroys off-screen items, so each `BannerAd` is disposed when it scrolls out.

## Design

- In `lib/screens/reels_screen.dart`, add a public pure helper that builds the
  list of feed entries from `List<Reel>` and a `bool adsEnabled`:
  one entry per reel plus an ad marker after every 5th. Store the result in
  state (`_entries`), rebuilt on load, on delete, on section/feed switch and on
  consent change. `itemCount = _entries.length`.
- Add private `_ReelAdSlot` (StatefulWidget). `initState` loads the `BannerAd`
  when enabled; listeners set the loaded ad; `dispose` cancels timers, removes
  listeners and disposes the ad. `didUpdateWidget` loads when `enabled` flips
  false→true and disposes when it flips true→false. Render only after load;
  failed slots are `SizedBox.shrink()`. Stable key per slot position.
- `itemBuilder` returns `_PostCard` for a reel entry and `_ReelAdSlot` for a
  marker. Reuse the existing callbacks and keys so current widget tests that
  find `reel-post-*` still match.
- One small unit test file for the entry-layout helper: 0, 4, 5, 6, 10, 11
  posts, with ads on and off; assert marker positions and item counts.

## Left to the builder

- Exact variable names and where the helper lives (top-level in
  `reels_screen.dart` keeps it in one file).
- Verify with `flutter analyze`, `flutter test` and `flutter build` (no
  `flutter run` per AGENTS.md).
