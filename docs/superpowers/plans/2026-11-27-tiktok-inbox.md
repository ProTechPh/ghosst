# TikTok-Style Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle `InboxScreen` to the TikTok inbox layout without changing DM behavior.

**Architecture:** Keep the existing `DirectChatClient` stream, announcements loader, and callbacks. Replace the header, add a horizontal circle shelf, and restyle the thread/notification rows.

**Tech Stack:** Flutter/Dart, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-27-tiktok-inbox-design.md`

## Global Constraints

- Preserve all constructor callbacks and injectable loaders.
- No new API endpoints or dependencies.
- Keep unread counts reported via `onUnreadChanged`.
- Verify with `flutter analyze` and `flutter test`.

## Review Focus

1. New message/search still work from the header icons.
2. World chat and DM thread taps still work.
3. Unread counts and badges still reflect thread state.
4. Announcements still visible.
5. 320px layout does not overflow.

---

### Task 1: Header, circle shelf, and rows

**Files:**
- Modify: `lib/screens/inbox_screen.dart`
- Test: `test/direct_chat_inbox_test.dart`

**Interfaces:**
- Consumes: existing `widget.client`, `widget.onOpenWorldChat`, `widget.onOpenThread`, `widget.loadAnnouncements`, `widget.searchUsers`.
- Produces: keyed `inbox-add`, `inbox-search`, `inbox-circles`, `inbox-notifications`, `inbox-world`, `thread-<id>`.

- [ ] **Step 1: Write failing widget tests**

Add tests asserting the keyed header actions, circle shelf, notification row, and a thread row with a coral unread badge; keep existing behavior tests.

- [ ] **Step 2: Run and confirm failure**

Run: `flutter test test/direct_chat_inbox_test.dart`
Expected: FAIL because the new keys/widgets do not exist.

- [ ] **Step 3: Implement the redesign**

Rebuild the app bar with add-people, centered title + chevron, and search. Add a horizontally scrolling circle shelf (`Create`, `World chat`, recent peers). Restyle notification and thread rows with larger avatars, bold names, previews, time, and coral unread badges. Preserve all taps and loaders.

- [ ] **Step 4: Run tests and analyzer**

Run: `flutter test` then `flutter analyze`.
Expected: all tests pass; no new analyzer errors.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/inbox_screen.dart test/direct_chat_inbox_test.dart docs/superpowers/specs/2026-11-27-tiktok-inbox-design.md docs/superpowers/plans/2026-11-27-tiktok-inbox.md
git commit -m "feat(ui): TikTok-style inbox"
```
