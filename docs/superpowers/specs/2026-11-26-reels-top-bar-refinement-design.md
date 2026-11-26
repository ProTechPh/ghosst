# Reels Top Bar Refinement — Design

## Intent

Replace the generic pill-shaped Reels feed switcher with a TikTok-style top bar that feels native to a full-screen media feed, while keeping wallet access obvious and touch targets accessible.

## Goals

- Center `Following` and `For You` as plain text tabs.
- Show the active tab with bold white text and a 2px white underline.
- Keep inactive tabs muted but readable over media.
- Keep the coin balance compact at the top-right with a 48dp touch target.
- Preserve feed switching, stale-response protection, and wallet navigation.

## Non-goals

- No new feed types, backend changes, or navigation changes.
- No cards, heavy borders, glow, or decorative motion.
- No changes to the Reels right rail, caption area, or bottom navigation.

## Constraints

- Use the existing Flutter widgets and `AppColors`/`AppText` tokens.
- Keep all primary controls at least 48dp.
- Maintain readability on bright media with a subtle top scrim.

## Approaches

### 1. Centered text tabs with active underline — chosen

Matches TikTok's feed hierarchy without adding visual weight. The coin balance remains a compact right-side utility.

### 2. Smaller pill tabs

Less bulky, but still reads as generic segmented navigation rather than a media-feed top bar.

### 3. Move coins into the right rail

Creates more top-bar space, but makes wallet access less discoverable and conflicts with the approved top-right coin balance.

## Design

```text
Following   For You          🪙 160
            ━━━━━
```

- The tab pair is centered in the safe area.
- The active label is white and bold; the inactive label is white at reduced opacity.
- A 2px white underline sits directly below the active label.
- Each tab retains a 48dp hit area and selected-state semantics.
- The coin control uses a compact translucent-dark surface, gold coin icon, gold figure, and no glow.
- A lightweight top-to-transparent black scrim protects contrast without becoming a visible band.

## Verification

- Update `test/reels_screen_test.dart` to assert centered text tabs, selected semantics/underline, 48dp targets, compact wallet access, and unchanged feed switching.
- Run the focused Reels suite, full Flutter tests, and analyzer.
- Visually verify on the Android emulator.
