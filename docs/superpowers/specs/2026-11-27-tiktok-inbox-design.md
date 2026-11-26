# TikTok-Style Inbox — Design

**Date:** 2026-11-27

## Intent

Restyle the Inbox screen to the TikTok inbox language shown by the user:
centered title with chevron, add-people and search icons, a horizontal circle
row, and bold message rows with coral unread badges.

## Goals

- Header: add-people (left), centered `Inbox` + chevron, search (right).
- Horizontal circle row: `Create`, `World chat`, and recent DM peers, with
  colored rings and names.
- Message rows: larger avatars, bold names, preview/time, coral badges,
  camera affordance for story-like entries.
- Announcements remain reachable as a notification row.

## Non-goals

- No stories API, no fake stories. Circle row uses existing DM peers.
- No new backend endpoints; no changes to DM behavior or callbacks.

## Constraints

- Keep `client`, `loadUsers`, `searchUsers`, `onOpenThread`, `onOpenWorldChat`,
  `onUnreadChanged`, `loadAnnouncements`, `embedded`.
- Existing tests must be updated, not deleted.
- `flutter run` never used; verify with `flutter analyze` and `flutter test`.

## Approaches

- **A (picked):** restructure `InboxScreen` widgets only, reusing current data.
- **B (rejected):** build a stories backend and real story viewer — out of scope.

## Decided how

Header actions, circle shelf, and row redesign in `lib/screens/inbox_screen.dart`;
tests in `test/direct_chat_inbox_test.dart` updated for the new layout.
