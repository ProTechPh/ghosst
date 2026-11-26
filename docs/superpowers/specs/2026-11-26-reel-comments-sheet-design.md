# TikTok-Style Reel Comments Sheet — Design

## Intent

Present Reel comments as a TikTok-style bottom sheet over the media, with familiar comment rows and a compact composer, while preserving the existing comment API and behavior.

## Goals

- Show comments in a rounded bottom sheet with a drag handle and centered `Comments` title.
- Keep the Reel visible behind the upper portion of the sheet.
- Use TikTok-like comment rows: avatar, name, text, relative time, heart icon, and `Reply`.
- Use a pill composer with avatar, quick emoji shortcuts, and send button.
- Preserve pagination, loading, empty/error/retry, posting, and failure messages.

## Non-goals

- No backend schema or endpoint changes.
- No functional comment likes, replies, or reads; the heart is visual-only until API support exists.
- No changes to Reel upload, feed, top bar, action rail, or navigation.

## Constraints

- Use existing `ReelComment` fields only.
- Keep all interactive controls at least 48dp.
- Keep text readable on the dark sheet.
- Do not retain a permanent feature flag.

## Approaches

### 1. Modal bottom sheet over the Reel — chosen

Closest to the requested TikTok interaction and keeps media context visible.

### 2. Restyle the existing full-screen route

Cheaper, but cannot reproduce the sheet-over-media presentation.

### 3. Add functional comment likes

Requires backend changes outside this UI pass, so it is deferred.

## Design

```text
        ───── drag handle ─────
             Comments

  [avatar] name  ·  2w
           Comment text
           Reply

  [avatar] Add a comment…      😍 🔥 👏 😮  ➤
```

- Sheet uses rounded top corners and a dark surface.
- Rows are compact with no card borders; heart icon is visual-only.
- Composer stays pinned at the bottom with a 48dp send target.
- Existing `Retry`, empty state, and posting snackbar remain.

## Verification

- Add widget assertions for sheet chrome, row layout, composer, and preserved callbacks.
- Run focused and full Reel comment suites.
- Visually verify on the Android emulator.
