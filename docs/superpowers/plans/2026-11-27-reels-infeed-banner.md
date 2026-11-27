# Reels In-Feed Banner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a passive AdMob banner after every 5th post in the reels feed, each slot owning its own load/dispose lifecycle.

**Architecture:** A pure helper turns the reel list into a typed entry list (`Reel` or ad-slot marker). `ReelsScreen` owns that list and one consent listener; each ad marker renders a small stateful slot that loads and disposes its own `BannerAd`. No backend, coin, or reward code is touched.

**Tech Stack:** Flutter/Dart, `google_mobile_ads: ^9.1.0`, existing `AdUnits` / `AdService`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-27-reels-infeed-banner-design.md`

## Global Constraints

- Ad unit IDs live only in `AdUnits` (`lib/services/ad_service.dart`); use `AdUnits.banner`.
- Ads are passive revenue only — never touch coins, never call reward/SSV code.
- Show a slot after every 5th reel post; only in the post list, never in Tutorials/Feedback. Applies to both the embedded home feed and the pushed creator-reel screen (same `ReelsScreen` widget).
- Banner size is fixed `AdSize.banner` (320×50) in a dark padded card; no inline adaptive in v1.
- Slot count is gated by `AdService.adsEnabled && widget.active`.
- No per-slot retry timers; a failed load renders nothing and is retried on the next feed rebuild.
- One consent listener on `AdService.adsEnabledNotifier` in `ReelsScreen`, removed in `dispose`.
- Verify with `flutter analyze`, `flutter test`, `flutter build`. **Do not run `flutter run`** (AGENTS.md).
- Builds require a flavor: `--flavor play` or `--flavor direct`.

## Review Focus

- Exactly 5 posts → exactly one slot at entry index 5, not at index 4. Test in Task 1.
- 4 posts → zero slots; the feed length stays equal to the post count. Test in Task 1.
- Ads disabled with 10 posts → zero slots, because the flag gates the helper. Test in Task 1.
- 10 posts → slots 0 and 1 at entry indices 5 and 11; appending posts must not renumber earlier slots. Test in Task 1.
- Empty feed → zero slots and `itemCount == 0`. Test in Task 1.

---

### Task 1: Feed entry layout helper

**Files:**
- Modify: `lib/screens/reels_screen.dart` (top-level, next to `ReelFeedPage` imports/classes)
- Test: `test/reels_feed_ads_test.dart` (new)

**Interfaces:**
- Consumes: `Reel` from `lib/services/models.dart`.
- Produces: `class ReelAdSlot { const ReelAdSlot(this.index); final int index; }` and `List<Object> reelsFeedEntries(List<Reel> reels, bool adsEnabled)` — one `Reel` per post plus a `ReelAdSlot` after every 5th post when `adsEnabled` is true; slot indices start at 0.

- [ ] **Step 1: Write the failing test**

Create `test/reels_feed_ads_test.dart` with a `_posts(int n)` helper that returns `n` minimal `Reel`s using the same required fields as the `_reel` helper in `test/reels_screen_test.dart` (`id`, `caption`, `posterUrl`, `images`, `createdAt`, `creator`, `likeCount`, `commentCount`, `isFollowing`, `isMine`; `creator` is a `PublicUser` with `id`, `displayName`, `username`, `createdAt`, `followerCount`, `followingCount`, `reelCount`). Use id `r$i` and empty `images`/`caption`. Then add these assertions:

```dart
test('one slot exactly after the 5th post', () {
  final e = reelsFeedEntries(_posts(5), true);
  expect(e.length, 6);
  expect(e[4], isA<Reel>());
  expect(e[5], isA<ReelAdSlot>());
  expect((e[5] as ReelAdSlot).index, 0);
});

test('four posts produce no slot', () {
  final e = reelsFeedEntries(_posts(4), true);
  expect(e.length, 4);
  expect(e.whereType<ReelAdSlot>(), isEmpty);
});

test('disabled ads produce no slot', () {
  final e = reelsFeedEntries(_posts(10), false);
  expect(e.length, 10);
  expect(e.whereType<ReelAdSlot>(), isEmpty);
});

test('slots on two pages keep stable indices', () {
  final first = reelsFeedEntries(_posts(5), true);
  final second = reelsFeedEntries(_posts(10), true);
  expect(second.length, 12);
  expect(second[5], isA<ReelAdSlot>());
  expect(second[11], isA<ReelAdSlot>());
  expect(
    first.whereType<ReelAdSlot>().single.index,
    equals(second.whereType<ReelAdSlot>().first.index),
  );
  expect(
    second.whereType<ReelAdSlot>().map((s) => s.index).toList(),
    [0, 1],
  );
});

test('empty feed has no entries', () {
  expect(reelsFeedEntries(const [], true), isEmpty);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/reels_feed_ads_test.dart`
Expected: compile failure — `reelsFeedEntries` / `ReelAdSlot` undefined.

- [ ] **Step 3: Implement the helper in `lib/screens/reels_screen.dart`**

Define the public `ReelAdSlot` marker and `reelsFeedEntries` exactly as described in Interfaces, using a `slot` counter that increments only when `(i + 1) % 5 == 0`. Do not import ad packages yet — Task 2 adds those imports with their uses.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/reels_feed_ads_test.dart`
Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/reels_screen.dart test/reels_feed_ads_test.dart
git commit -m "feat: add reels in-feed ad layout helper"
```

---

### Task 2: Ad slot widget and feed wiring

**Files:**
- Modify: `lib/screens/reels_screen.dart` (state fields, `initState`, `dispose`, `didUpdateWidget`, `_load`, `_deleteReel`, `_buildBody`, new private widget)

**Interfaces:**
- Consumes: `ReelAdSlot`, `reelsFeedEntries(reels, enabled)` from Task 1; `AdUnits.banner`, `AdService.adsEnabled`, `AdService.adsEnabledNotifier`, `AdService.logAdError` from `lib/services/ad_service.dart`.
- Produces: `List<Object> _entries` in `_ReelsScreenState`, rebuilt by `void _rebuildEntries()`; private `_ReelAdSlot` keyed `ValueKey('reel-ad-slot-${slot.index}')`.

- [ ] **Step 1: Add the private `_ReelAdSlot` StatefulWidget in `reels_screen.dart`**

Signature: `const _ReelAdSlot({required this.slot})`, `final ReelAdSlot slot`. In `initState`, if `AdService.adsEnabled` and mounted, create `BannerAd(adUnitId: AdUnits.banner, size: AdSize.banner, request: const AdRequest(), listener: BannerAdListener(onAdLoaded: ..., onAdFailedToLoad: ...))` and `await ad.load()`. On loaded, `setState(() => _ad = ad)` when mounted, otherwise dispose. On failure, dispose the ad, call `AdService.logAdError('Banner', AdUnits.banner, error, action: 'load')`, and leave `_ad` null. In `dispose`, dispose `_ad` then call `super.dispose()`. Build: `SizedBox.shrink()` while `_ad == null`; otherwise a `SizedBox(width: 320, height: 50)` containing a `ColoredBox(color: AppColors.bg, child: AdWidget(ad: _ad!))`. Add a `Semantics` label `'Advertisement'` around it. No retry timer, no consent listener inside the slot.

- [ ] **Step 2: Wire `_entries` into `_ReelsScreenState`**

Add `List<Object> _entries = const [];` and `void _rebuildEntries() => setState(() => _entries = reelsFeedEntries(_reels, widget.active && AdService.adsEnabled));`. Add the imports for `package:google_mobile_ads/google_mobile_ads.dart` and `../services/ad_service.dart` here. In `initState`, after the existing scroll listener setup, add `AdService.instance.adsEnabledNotifier.addListener(_rebuildEntries)`. In `dispose`, remove that listener before `super.dispose()`. In `didUpdateWidget`, call `_rebuildEntries()` when `widget.active != oldWidget.active`. In `_load`'s success `setState`, after `_reels = items;`, set `_entries = reelsFeedEntries(_reels, widget.active && AdService.adsEnabled);`. In `_deleteReel`'s success `setState`, rebuild `_entries` the same way.

- [ ] **Step 3: Change the reels list builder**

In `_buildBody`'s `ListView.separated`, set `itemCount: _entries.length`. In `itemBuilder`, read `final entry = _entries[i];` and branch: if `entry is ReelAdSlot`, return `_ReelAdSlot(key: ValueKey('reel-ad-slot-${entry.index}'), slot: entry)`. Otherwise cast to `Reel` and keep the existing `_PostCard` construction and all callbacks/keys unchanged. Keep `_feedScroll`, the divider separator, and the section conditions as-is.

- [ ] **Step 4: Verify targeted tests**

Run: `flutter test test/reels_screen_test.dart test/reels_feed_ads_test.dart`
Expected: all tests PASS (existing reels tests see `adsEnabled == false`, so no slot widgets appear).

- [ ] **Step 5: Verify lint and build**

Run: `flutter analyze`
Expected: `No issues found`.
Run: `flutter build apk --release --flavor direct`
Expected: successful build.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/reels_screen.dart
git commit -m "feat: show in-feed banner ads in the reels feed"
```
