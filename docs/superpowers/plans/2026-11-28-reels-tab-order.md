# Reels tab order and gesture cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show **For You** first on Home and remove the unused swipe gesture that switches Reels tabs.

**Architecture:** Reorder the existing `_FeedTab` widgets and delete only the top-area `Listener` swipe state/handlers. Keep tap navigation, semantics keys, horizontal scrolling, and the reel-image `PageView`.

**Tech Stack:** Flutter/Dart, existing widget tests.

**Spec:** `docs/superpowers/specs/2026-11-28-reels-tab-order-design.md`

## Global Constraints

- Do not change feed APIs, content, bottom navigation, or image carousel behavior.
- Keep all four tabs and their existing semantics keys.
- Do not run `flutter run`; verify with tests, analyze, and build.
- Do not manually bump the build number.

## Review Focus

- **First open:** For You is selected and visible without scrolling.
- **Narrow phone:** all four tabs remain reachable through horizontal scrolling and taps.
- **Removed gesture:** dragging the top tab area does not change sections.
- **Carousel gesture:** horizontal swipe inside a reel image still changes images.
- **Tutorial/Feedback access:** both sections still load and open through taps.

---

### Task 1: Reorder tabs and remove tab swipe navigation

**Files:**
- Modify: `lib/screens/reels_screen.dart`
- Modify: `test/reels_screen_test.dart`
- Create: `docs/superpowers/specs/2026-11-28-reels-tab-order-design.md`
- Create: `docs/superpowers/plans/2026-11-28-reels-tab-order.md`

**Interfaces:**
- Consumes: existing `_FeedTab`, `_switchSection`, `_section`, `_feed`, and reel carousel.
- Produces: tab order `for-you`, `following`, `tutorials`, `feedback`; no `reels-swipe-area` widget.

- [x] Update the tab-order test to expect For You, Following, Tutorials, Feedback.
- [x] Replace the swipe-cycling test with a test asserting For You is selected on first open, no `reels-swipe-area` exists, and a top-area drag leaves For You selected.
- [x] Run `flutter test test/reels_screen_test.dart` and verify the updated tests fail on the old order/gesture.
- [x] Reorder the `_FeedTab` widgets in `reels_screen.dart`.
- [x] Delete `_swipeStartX`, `_swipeStartY`, `_onSwipeDown`, `_onSwipeUp`, and the `Listener` wrapper/key while preserving the scrim and tab layout.
- [x] Run `flutter test test/reels_screen_test.dart` and verify all Reels tests pass, including carousel swipe.
- [x] Run `flutter analyze --no-fatal-infos lib/screens/reels_screen.dart test/reels_screen_test.dart` and verify no new issues beyond the existing Material deprecation infos.
- [x] Run the full `flutter test` suite and verify all tests pass.
- [x] Build `flutter build apk --release --flavor direct --android-skip-build-dependency-validation` and verify exit 0.
- [x] Commit the UI/test/docs change.
