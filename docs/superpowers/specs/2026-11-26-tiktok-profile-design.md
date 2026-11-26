# TikTok-Style Own Profile — Design

**Date:** 2026-11-26
**Source design system:** `DESIGN.md` (TikTok brand extraction)

## Intent

The user said the own-profile screen looks ugly and does not read as TikTok. Rebuild
`lib/screens/profile_hub_screen.dart` so it reads as a TikTok profile while keeping
every existing utility reachable.

## Goals

- Own profile follows the TikTok profile grammar: black header band, centered
  avatar/name/handle/bio, oversized social numbers, one Posts label, edge-to-edge
  reel grid.
- Utility actions (Keys, Wallet, Feedback, Admin) move into a top-bar overflow
  menu; no function is removed.
- Visual tokens come from `DESIGN.md`, translated to the app's dark canvas.

## Non-goals

- No changes to public-user profiles (`UserProfileScreen`), the Reels feed, or
  any API/PHP code.
- No Liked tab — the API has no liked-reels endpoint; a dead tab would be fake.
- No new font assets: TikTok Sans is not bundled, so the existing sans fallback
  stays.

## Constraints

- `DESIGN.md`: black/white stage, coral `#FE2C55` as the primary/active accent,
  cyan `#25F4EE` only as a short highlight, TikTok type scale, 8–24px radii,
  44px touch targets, **no** gradients, glassmorphism, or glow stacks.
- The app is dark-mode; keep the dark canvas rather than the web doc's white one.
- Settings and share stay reachable from the top bar.
- Existing tests must be updated and all must pass.

## Approaches

- **A (picked):** full TikTok profile; utilities live behind a top-bar overflow
  menu. Chosen because the four hub chips are the least TikTok-like part of the
  screen, and nothing is lost by moving them.
- **B (rejected):** keep the chips as compact pills under the stats. Smaller diff
  but the screen still reads as a dashboard, not a profile.

## Decided layout

1. Top bar: `Profile` title, Share icon, and a `⋮` overflow menu containing
   Settings, Keys, Wallet, Feedback, and Admin (admin only).
2. Solid black header band; centered avatar overlapping its lower edge; bold
   display name; `@handle`; one-line bio.
3. Stats row: numbers set large with small muted labels for Following, Followers,
   Reels.
4. `Posts` label with a short coral underline; 3-column reel grid with 2px gaps,
   full-bleed, no `YOUR REELS` heading.
5. Coral reserved for the active indicator/primary action; cyan appears only as
   a small accent, never as a page fill.

## Left to builder

- Edit `lib/screens/profile_hub_screen.dart` only; keep all callbacks.
- Update `test/profile_hub_screen_test.dart` so utility assertions open the
  overflow menu first.
- Verify with `flutter analyze` and `flutter test`.
