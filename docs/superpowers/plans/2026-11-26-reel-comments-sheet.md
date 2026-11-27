# TikTok-Style Reel Comments Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Present Reel comments in a TikTok-style bottom sheet over the media with a pill composer and familiar comment rows.

**Architecture:** Turn `ReelCommentsScreen` into sheet content instead of a full-screen route and open it with `showModalBottomSheet` from `ReelsScreen`. Keep all loading, pagination, posting, empty/error, and callback behavior unchanged.

**Tech Stack:** Flutter/Dart, `showModalBottomSheet`, existing `ReelComment` model and `AppColors`/`AppText` tokens.

**Spec:** `docs/superpowers/specs/2026-11-26-reel-comments-sheet-design.md`

## Global Constraints

- No backend schema or endpoint changes.
- Comment hearts are visual-only; no persistent like state.
- Keep all interactive controls at least 48dp.
- Keep text readable on the dark sheet.
- No permanent feature flag.
- Preserve pagination, loading, empty/error/retry, posting, and failure messages.

## Review Focus

- A 320px viewport must show the sheet and composer without overflow.
- Long names and comment text must not break row layout.
- Loading, empty, and error states must remain visible inside the sheet.
- A failed post must keep the draft and still show the failure snackbar.
- The Reel must remain visible above the sheet.

---

### Task 1: Build the comments sheet

**Files:**
- Modify: `lib/screens/reel_comments_screen.dart`
- Modify: `lib/screens/reels_screen.dart`
- Modify: `test/reel_comments_screen_test.dart`
- Modify: `test/reels_screen_test.dart`

**Interfaces:**
- Consumes: existing `ReelCommentsScreen(reelId, load, submit)` API and `ReelsScreen._openComments`.
- Produces: sheet content that can be hosted by a modal bottom sheet; no changed public constructor signatures.

- [ ] **Step 1: Write failing sheet assertions**

In `test/reel_comments_screen_test.dart`, add a test named `comments sheet uses TikTok chrome and keeps composer actions` that:

- pumps a 320px-wide `ReelCommentsScreen` with one long-named comment and long text;
- asserts a keyed drag handle and centered `Comments` title;
- asserts the comment row shows display name, full text, and `Reply` without overflow;
- asserts a visual-only heart action with a 48dp target;
- asserts a keyed pill composer with a 48dp send button and at least three emoji shortcuts;
- enters text and taps send, asserting the injected `submit` callback receives it;
- with a failing submit, asserts the draft remains and the failure snackbar appears.

In `test/reels_screen_test.dart`, add a test named `comments open as a modal sheet over the Reel` that:

- opens comments from a Reel;
- asserts a modal bottom sheet exists;
- asserts the Reel image remains in the widget tree behind it.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `flutter test test/reel_comments_screen_test.dart test/reels_screen_test.dart --plain-name "sheet"`
Expected: FAIL because the current comments screen is a full-screen route with plain rows.

- [ ] **Step 3: Convert `ReelCommentsScreen` to sheet content**

In `lib/screens/reel_comments_screen.dart`:

- remove the `Scaffold`/`AppBar` shell;
- return a keyed dark container with rounded top corners, drag handle, and centered `Comments` title;
- render comments as borderless rows with avatar, name, text, relative time, visual heart, and `Reply`;
- render loading, empty, and error/retry states inside the sheet body;
- keep the pill composer pinned with avatar, hint, emoji shortcuts, and 48dp send action;
- preserve the existing load, submit, retry, and snackbar behavior.

- [ ] **Step 4: Open comments as a modal bottom sheet**

In `lib/screens/reels_screen.dart`, change `_openComments` to call `showModalBottomSheet` with transparent background, scroll-controlled sizing, a maximum height of 82% of the viewport, and `ReelCommentsScreen` as its content.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run: `flutter test test/reel_comments_screen_test.dart test/reels_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Run full regression suites**

Run: `flutter test test/reels_screen_test.dart test/reel_comments_screen_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/reel_comments_screen.dart lib/screens/reels_screen.dart test/reel_comments_screen_test.dart test/reels_screen_test.dart docs/superpowers/specs/2026-11-26-reel-comments-sheet-design.md docs/superpowers/plans/2026-11-26-reel-comments-sheet.md
git commit -m "feat(ui): restyle Reel comments as TikTok sheet"
```
