# Performance ledger

## Baseline (2026-11-08, before fix)

- `flutter analyze`: clean
- `flutter test`: 126 passed
- No on-device profile run — bottleneck identified by code inspection (serial
  awaits), not by a device trace. Numbers below are expected, not measured.

## Attempts

| Idea | Baseline → Result | Verdict | Why |
|---|---|---|---|
| Parallelize `StoreScreen._load` stock counts + owned set (`Future.wait`) | Store: N serial round-trips → 1 parallel batch | kept | Removes N+1 waterfall on the first store paint. `availableCount` already folds failures to `-1`, so the batch cannot fail on one product. Tests: 126 green. **Needs a device re-measure with a real admin account and 10+ key products.** |
| Parallelize `Backend.myClaims` download tickets | Purchases: N serial ticket fetches → 1 parallel batch | kept | Same N+1 shape as above, in the purchases path. Per-claim `ApiException` still folds to null, so one bad ticket no longer stalls the rest. Tests: 126 green. |
| Run `coins()` alongside `_refresh`'s other fetches in `HomeShell` | Shell open: coins serial then 3 parallel → 4 parallel | kept | One round-trip off every shell open. Error handling preserved (last known balance kept, reason still snacked). Tests: 126 green. |
| Decode images at display size (`cacheWidth`/`cacheHeight`) — Store `_cover`, `LogoBadge`, splash logo | Full Cloudinary/logo decode per card/badge → 2x display-size decode | kept | `Backend.imageUrl` ignores its `width` arg, so cards held 800px+ bitmaps for ~200px slots; the 250KB `logo.jpg` decoded at full size for a 28px badge on every frame. 2 lines per site, no visual change at 2x. Tests: 126 green. **Needs a device scroll check (low-end Android) to confirm.** |
| Lazy-load `MyKeysScreen` + `AnnouncementsScreen` on first tab visit (active-gate, same as `ChatScreen`) | Shell open fired claims + N product fetches + announcements for hidden tabs → zero until tapped | kept | `IndexedStack` mounts all tabs at once, so `initState._load()` paid for Purchases/News even when never opened. First activation shows skeleton/error (`_hasLoaded` gate), later activations refresh silently. `AnnouncementsScreen` defaults `active=true` so existing tests/standalone use are unchanged. Tests: 126 green. **Needs a tap-through on device to confirm no stale-tab flash.** |
| Run `coins()` alongside other fetches in `WalletScreen._load` + `ProfileScreen._load` (same shape as `HomeShell._refresh`) | Wallet/Profile: coins serial then 2 parallel → 3 parallel | kept | Same one-round-trip saving as HomeShell, applied to the remaining two screens that shared the serial shape. Error mapping preserved (stale balance + error string). Tests: 126 green. |
| Parallelize `AdminScreen._showKeys` `reloadCounts` (2 totals + N duration counts) | Admin stock refresh: 2+N serial round-trips → 1 parallel batch | kept | Last remaining serial waterfall from the `await Backend.` sweep. Whole-batch failure still lands in the same `catch` (counts are decoration), so dialog behavior is unchanged. Tests: 126 green. |
| Hoist `groupDigits` `RegExp` to a static (micro-benchmark 100k calls) | old 269–312ms → new 246–286ms | reverted | Runs overlap — inside noise for real usage (~100s/sec). Neutral changes are a revert; the dead idea stays dead. |
| Guard: `AnnouncementsScreen` hidden tab must not fetch until activated | calls=0 hidden → calls=1 on activation | kept | Covers the lazy-load fix against regression (old eager `initState` fails this test). Full suite 127 green. |
| Remaining `Image.network` sites decode at 2x slot — product detail, YouTube thumb, download cover, my-apps cover, admin thumbs (3) | Full decode → 2x slot decode | kept | Same no-visual-change fix as Store/logo, applied everywhere the sweep had missed. `hqdefault` pinned to its 480×360 native size. Tests: 127 green. |
| Grain-overlay dots 2600 → 1100; card blur radii 40/24/32 → 28/18/24; `GlowCard` 30/18 → 22/14 | Same visuals, ~30–60% less fill/blur work | kept (unmeasured) | Explicit "optimize all" request — these trade a little softness for GPU. **Must eyeball Store/Settings on a low-end phone: if cards look flat or grain looks sparse, revert the blur/dots lines only (keep the image fixes).** Tests: 127 green, but tests cannot see blur quality. |

## Guard

Regression guard: `hidden tab does not fetch until activated` in
`test/announcements_screen_test.dart` fails if News goes back to eager
`initState` loading. No synthetic CI budget added. Network fixes reorder
concurrent fetches to `Future.wait` (the pattern `MyKeysScreen` already
uses); correctness is covered by 127 tests plus `flutter analyze`. The last
three rows (grain + blur radii) shipped on explicit "optimize all" request
and are **unmeasured** — next step is `flutter run --flavor play` +
DevTools scroll trace; if FPS did not move or cards look flat, revert those
lines (they are isolated in `premium.dart`/`arcade.dart`/`theme.dart`).
