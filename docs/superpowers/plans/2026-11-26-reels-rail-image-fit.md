# Reels Rail and Image Fit Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Reels action rail TikTok-style and display carousel images uncropped with `BoxFit.contain`.

**Architecture:** Keep `_ReelPage` state and callbacks unchanged. Replace only image fitting and action-rail presentation, using existing counts, keys, and confirmation flows.

**Tech Stack:** Flutter/Dart, `CachedNetworkImage`, existing `Reel` counts and `AppColors`/`AppText` tokens.

**Spec:** `docs/superpowers/specs/2026-11-26-reels-rail-image-fit-design.md`

## Global Constraints

- No new actions, backend fields, feed behavior, or navigation changes.
- Use `BoxFit.contain` on black for Reel images.
- Keep all action targets at least 48dp.
- Use existing `Reel.likeCount` and `Reel.commentCount`.
- Preserve profile, like, comment, report, and delete callbacks and confirmations.

## Review Focus

- Portrait, landscape, and very wide images must remain fully visible without distortion.
- Large like/comment counts must not overflow the narrow action rail.
- The plus badge must not intercept the avatar profile tap.
- Own reels must not show a follow/plus badge, while other creators' reels must.
- Liked state must remain red and announce its state accessibly.

---

### Task 1: Refine Reel image fit and action rail

**Files:**
- Modify: `lib/screens/reels_screen.dart`
- Modify: `test/reels_screen_test.dart`

**Interfaces:**
- Consumes: `Reel.images`, `Reel.likeCount`, `Reel.commentCount`, `Reel.isMine`, and existing `onProfile`/`onLike`/`onComments`/`onDelete`/`onReport` callbacks.
- Produces: no public interface changes; the Reel page renders uncropped media and a TikTok-style action rail.

- [ ] **Step 1: Write failing rail and image-fit assertions**

Add a widget test named `Reel rail shows full images, counts, and TikTok-style actions` that:

- pumps a reel with `likeCount: 1200`, `commentCount: 34`, and a non-owner creator;
- asserts the `CachedNetworkImage` for the Reel uses `BoxFit.contain`;
- asserts visible compact count labels `1.2K` and `34`;
- asserts a keyed plus badge exists and the avatar/profile key still opens the profile;
- asserts like, comment, and report targets are each at least 48dp;
- taps like and asserts the filled heart icon is red;
- asserts no plus badge appears when `isMine: true`.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/reels_screen_test.dart --plain-name "Reel rail shows full images, counts, and TikTok-style actions"`
Expected: FAIL because the image uses `BoxFit.cover`, counts/badge are absent, and the rail uses plain icon buttons.

- [ ] **Step 3: Implement the uncropped image and action rail**

In `lib/screens/reels_screen.dart`:

- change the Reel `CachedNetworkImage.fit` to `BoxFit.contain`;
- replace the plain action column with reusable private rail-item widgets for profile, like, comment, delete, and report;
- show compact counts beneath like/comment;
- add a cyan plus badge for non-own reels without blocking the avatar tap;
- use filled white heart/comment icons, red liked state, subtle shadows, and 48dp targets;
- preserve every existing `ValueKey`, callback, and confirmation flow.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `flutter test test/reels_screen_test.dart --plain-name "Reel rail shows full images, counts, and TikTok-style actions"`
Expected: PASS.

- [ ] **Step 5: Run the full Reels regression suite**

Run: `flutter test test/reels_screen_test.dart`
Expected: PASS, including top-bar, carousel, profile, like/unlike, comments, report, delete, empty/error, and initial-selection behavior.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/reels_screen.dart test/reels_screen_test.dart docs/superpowers/specs/2026-11-26-reels-rail-image-fit-design.md docs/superpowers/plans/2026-11-26-reels-rail-image-fit.md
git commit -m "feat(ui): refine Reels rail and image fit"
```
