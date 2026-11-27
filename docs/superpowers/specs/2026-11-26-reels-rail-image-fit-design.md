# Reels Rail and Image Fit Refinement — Design

## Intent

Make the Reels action rail read like TikTok while showing uploaded carousel images in full, without cropping or changing existing actions.

## Goals

- Use `BoxFit.contain` on a black media surface so the whole image is visible.
- Give the creator avatar a cyan follow/plus badge for other creators.
- Use larger filled white heart and comment icons with visible counts.
- Keep delete and report actions clear, large, and reachable.
- Preserve profile, like, comment, report, and delete callbacks.

## Non-goals

- No new actions, backend fields, or feed behavior.
- No share/bookmark actions in this pass.
- No changes to captions, top bar, carousel dots, or bottom navigation.

## Constraints

- Keep all action targets at least 48dp.
- Use existing `Reel.likeCount` and `Reel.commentCount`.
- Maintain contrast over bright media with subtle text shadows.
- Preserve the current report and delete confirmation flows.

## Approaches

### 1. TikTok-style rail with full-image contain — chosen

Matches the requested visual hierarchy and fixes the cropped-image problem directly.

### 2. Enlarge existing outline icons only

Less work, but still reads as generic Material controls rather than a media-action rail.

### 3. Move report/delete into an overflow menu

Closer to TikTok's minimal rail, but hides existing safety actions and changes interaction cost.

## Design

```text
        [avatar]
          +
        ♥  12
        💬 4
        🗑
        ⚑
```

- Media uses `BoxFit.contain`, centered on black.
- Avatar remains tappable; a cyan plus badge appears for non-own reels.
- Heart and comment use filled icons with counts beneath.
- Liked hearts stay red; all other action icons stay white.
- Delete appears only on the owner's reel; report remains available.
- Text and icons receive subtle shadows for media contrast.

## Verification

- Add widget assertions for `BoxFit.contain`, count labels, the plus badge, and 48dp action targets.
- Run the focused and full Reels suites.
- Visually verify on the Android emulator with a cropped-looking source image.
