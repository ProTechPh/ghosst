# Reels Top Bar Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Reels pill switcher with centered TikTok-style text tabs and a compact top-right coin balance.

**Architecture:** Keep the existing `ReelsScreen` state and feed-loading logic unchanged. Replace only the embedded top-bar composition and `_FeedChip` presentation, using a centered tab pair, active underline, 48dp hit areas, a subtle top scrim, and the existing `CoinPill`.

**Tech Stack:** Flutter/Dart, existing `AppColors`, `AppText`, `AppSpace`, and `kTouchMin` tokens.

**Spec:** `docs/superpowers/specs/2026-11-26-reels-top-bar-refinement-design.md`

## Global Constraints

- No backend, API, feed-state, navigation, or wallet behavior changes.
- Use plain text tabs with bold white active text and a 2px white underline.
- Keep inactive tabs muted but readable over media.
- Keep every primary top-bar control at least 48dp.
- No cards, heavy borders, glow, or decorative motion.

## Review Focus

- Bright media behind the top controls must remain readable through a subtle top scrim.
- A 320px-wide viewport must fit the centered tab pair and coin control without overflow.
- Both feed tabs must retain 48dp touch targets and selected-state semantics.
- The active underline must follow the selected feed after a tap.
- Feed switching and wallet navigation must keep their existing behavior.

---

### Task 1: Refine the embedded Reels top bar

**Files:**
- Modify: `lib/screens/reels_screen.dart`
- Modify: `test/reels_screen_test.dart`

**Interfaces:**
- Consumes: existing `_feed`, `_load(reset: true)`, `widget.coins`, and `widget.onOpenWallet`.
- Produces: no new public interface; the embedded top bar renders centered text tabs, an active underline, a top scrim, and the existing coin control.

- [ ] **Step 1: Write failing top-bar assertions**

Add a `test/reels_screen_test.dart` widget test named `embedded top bar uses centered text tabs and compact wallet control` that:

- sets a 320px-wide viewport and pumps one reel with `coins: 160`;
- asserts `For You` and `Following` each have a 48dp-tall tappable ancestor;
- asserts the centered tab pair is horizontally centered within the top bar;
- asserts the active `For You` semantics is selected and has a 2px underline descendant;
- taps `Following` and asserts its semantics becomes selected with the underline;
- asserts the coin balance remains visible and opens the wallet;
- asserts a keyed top scrim exists and no `ChoiceChip` is present.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/reels_screen_test.dart --plain-name "embedded top bar uses centered text tabs and compact wallet control"`
Expected: FAIL because the current implementation uses left-aligned `ChoiceChip` widgets.

- [ ] **Step 3: Replace the embedded top-bar composition**

In `lib/screens/reels_screen.dart`:

- replace `_FeedChip` with a plain text tab widget that exposes a `ValueKey`, 48dp minimum height, selected semantics, and a 2px underline when selected;
- center `Following` and `For You` in the safe area;
- keep the coin control right-aligned and compact;
- add a subtle top-to-transparent black scrim keyed `reels-top-scrim` behind the controls;
- preserve the existing `setState` and `_load(reset: true)` callbacks exactly.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `flutter test test/reels_screen_test.dart --plain-name "embedded top bar uses centered text tabs and compact wallet control"`
Expected: PASS.

- [ ] **Step 5: Run the full Reels regression suite**

Run: `flutter test test/reels_screen_test.dart`
Expected: PASS, including stale-feed protection, carousel, actions, empty/error states, wallet access, and initial-reel selection.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/reels_screen.dart test/reels_screen_test.dart docs/superpowers/specs/2026-11-26-reels-top-bar-refinement-design.md docs/superpowers/plans/2026-11-26-reels-top-bar-refinement.md
git commit -m "feat(ui): refine Reels top bar"
```
