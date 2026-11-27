# X-Style Reels Feed — Design

**Date:** 2026-11-27

## Intent

Replace the full-screen vertical reels viewer with an X/Twitter-style scrolling
timeline of post cards, as shown by the user.

## Goals

- Feed is a vertically scrolling `ListView` of posts, one reel per card.
- Each card: avatar, display name, `@handle`, verified/admin badge, relative
  time, caption text, image, and an action row (comments, like, share, views).
- Top tab row (Tutorials / Feedback / Following / For You) and horizontal swipe
  stay as-is.
- Existing actions still work: like, follow, comments, profile, report, delete.

## Non-goals

- No bottom-nav changes (stays TikTok-style per user's scope choice).
- No video playback; reels remain image carousels/cards.
- No new API endpoints.

## Constraints

- Keep `ReelsScreen` public constructor and callbacks intact.
- Keep injectable `load`, `loadComments`, `submitComment`, etc. for tests.
- `flutter run` never used; verify with `flutter analyze` and `flutter test`.

## Approaches

- **A (picked):** convert the feed body to a scrollable list of cards.
- **B (rejected):** keep PageView and fake card overlays — not a real timeline.

## Decided how

`lib/screens/reels_screen.dart` feed builder becomes `ListView.separated` with a
new `_PostCard` widget; tests updated for card layout and preserved actions.
