# Reels tab order and gesture cleanup design

## Intent
Make the default **For You** feed immediately visible when Home opens and remove the unused horizontal tab-switch gesture.

## Goals
- Order the Reels top tabs as **For You, Following, Tutorials, Feedback**.
- Keep **For You** selected on first open.
- Remove the top-area swipe handler that changes tabs.
- Preserve tab tap navigation and reel-image carousel swiping.

## Non-goals
- No feed API, ranking, content, or backend changes.
- No removal of Tutorials or Feedback.
- No change to bottom navigation or other gesture handlers.

## Constraints
- Keep the existing horizontal `SingleChildScrollView` so all tabs remain reachable on narrow phones.
- Keep existing semantics keys and selected states for accessibility/tests.
- Do not remove the image `PageView` swipe behavior.

## Approaches
1. Keep tab order and auto-scroll to For You: makes the default visible but leaves Tutorials first in the row. Not chosen.
2. Reorder tabs and remove tab swipe navigation (chosen): matches the requested default hierarchy and deletes unused gesture code.
3. Reorder tabs but keep swipe navigation: preserves an unused interaction the owner asked to remove. Not chosen.

## Design
- In `lib/screens/reels_screen.dart`, move the `for-you` `_FeedTab` before `following`, then `tutorials`, then `feedback`.
- Delete `_swipeStartX`, `_swipeStartY`, `_onSwipeDown`, `_onSwipeUp`, the `Listener` wrapper, and the `reels-swipe-area` key.
- Keep `_switchSection`, `_FeedTab` tap handlers, and the reel carousel `PageView`.
- Update `test/reels_screen_test.dart` to assert the new order, default selection, tap navigation, and that a top-area drag no longer changes tabs.
