# TikTok-Style Own Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the own-profile screen as a TikTok-style profile using `DESIGN.md` tokens, with utilities moved into a top-bar overflow menu.

**Architecture:** Keep `ProfileHubScreen` and all its existing callbacks; change only its chrome and reel grid. Add the two TikTok signature colors to `AppColors` in `theme.dart`, then rebuild the screen as a black header band with overlapping avatar, oversized stats, a Posts label, an edge-to-edge grid, and a `⋮` menu. No API, model, or navigation changes.

**Tech Stack:** Flutter/Dart, existing `AppColors`/`AppText` tokens, `PopupMenuButton`, `flutter_test` widget tests.

**Spec:** `docs/superpowers/specs/2026-11-26-tiktok-profile-design.md`

## Global Constraints

- Follow `DESIGN.md`: black/white stage; coral `#FE2C55` for active/primary accent; cyan `#25F4EE` only as a short highlight; 8–24px radii; 44px touch targets; no gradients, glassmorphism, or glow stacks.
- Keep the app's dark canvas; do not switch to the web doc's white canvas.
- No Liked tab and no new font assets (TikTok Sans is not bundled).
- `flutter run` is never used for verification; use `flutter analyze` and `flutter test`.
- Do not bump the build number by hand and do not push to `main`.

## Review Focus

1. Non-admin accounts must never see the Admin menu item → Task 1 asserts `Admin` is absent for `isAdmin: false`.
2. Every utility must still work from the menu → Task 1 taps Keys, Wallet, Feedback, Admin, Settings, Share and asserts each callback fires.
3. Reel load failure must still show Retry, not a fake empty grid → Task 2 keeps the existing failure test and asserts Retry.
4. At 320px the large stats and grid must not overflow → Task 2 pumps 320x640 and asserts no exception.
5. The four utility labels must not appear on the main profile surface → Task 1 asserts they are `findsNothing` before the menu is opened.

---

### Task 1: TikTok profile chrome and overflow menu

**Files:**
- Modify: `lib/theme.dart` (add `tiktokCoral`, `tiktokCyan` to `AppColors`)
- Modify: `lib/screens/profile_hub_screen.dart` (app bar, header, identity, stats, Posts label)
- Test: `test/profile_hub_screen_test.dart`

**Interfaces:**
- Consumes: existing `ProfileHubScreen` constructor fields and callbacks (unchanged).
- Produces: `ValueKey('profile-tiktok-header')` band, `ValueKey('profile-posts-indicator')` coral underline, `ValueKey('profile-menu')` popup button. No public API changes.

- [ ] **Step 1: Write the failing tests** in `test/profile_hub_screen_test.dart`

Add `tiktok profile chrome moves utilities behind an overflow menu` that pumps a 320x640 screen with `isAdmin: true`, injected `loadProfile`/`loadReels`, and callback recorders. Assert: `find.byKey(ValueKey('profile-tiktok-header'))` findsOneWidget; `find.text('Posts')` findsOneWidget; `find.byKey(ValueKey('profile-posts-indicator'))` findsOneWidget; `find.text('Keys')`, `find.text('Wallet')`, `find.text('Feedback')`, `find.text('Admin')` all `findsNothing`; `find.byIcon(Icons.settings_outlined)` `findsNothing`. Then tap `find.byKey(ValueKey('profile-menu'))`, and assert each of `Settings`, `Keys`, `Wallet`, `Feedback`, `Admin` is visible; tap each and assert its recorder fired; reopen the menu and tap `Share`, assert share fired.

Add `non-admin profile menu hides Admin` that pumps `isAdmin: false`, opens the menu, and asserts `Admin` `findsNothing` while `Keys` is present.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/profile_hub_screen_test.dart --plain-name "menu"`
Expected: FAIL because the header, Posts label, and menu do not exist yet.

- [ ] **Step 3: Add the tokens and rebuild the chrome**

In `lib/theme.dart`, add to `AppColors`: `static const Color tiktokCoral = Color(0xFFFE2C55);` and `static const Color tiktokCyan = Color(0xFF25F4EE);`.

In `lib/screens/profile_hub_screen.dart`: replace the app-bar actions with Share plus `PopupMenuButton<String>` keyed `profile-menu`; keep `onOpenSettings`, `onOpenKeys`, `onOpenWallet`, `onOpenFeedback`, and the admin-gated `onOpenAdmin` as menu items mapped in `onSelected`. Replace the avatar/name block with a solid black band keyed `profile-tiktok-header`, the avatar overlapping its lower edge, then bold name, `@handle`, and the one-line bio. Replace the stats row with large numbers and small muted labels. Remove the four utility tiles. Add `Posts` text and a 24x2 coral underline keyed `profile-posts-indicator`. Leave the reels section children for Task 2.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/profile_hub_screen_test.dart`
Expected: PASS, including the existing dashboard tests updated so utility assertions open the menu first.

- [ ] **Step 5: Commit**

```bash
git add lib/theme.dart lib/screens/profile_hub_screen.dart test/profile_hub_screen_test.dart
git commit -m "feat(ui): TikTok-style profile chrome with utility menu"
```

### Task 2: Edge-to-edge reel grid

**Files:**
- Modify: `lib/screens/profile_hub_screen.dart` (reels section only)
- Test: `test/profile_hub_screen_test.dart`

**Interfaces:**
- Consumes: `_reels`, `_reelsLoading`, `_reelsFailed`, `_loadReels(reset: true)` from Task 1.
- Produces: no new public API; grid uses `SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: 0.75)`.

- [ ] **Step 1: Write the failing test** in `test/profile_hub_screen_test.dart`

Add `own reels render as an edge-to-edge TikTok grid` that pumps with `loadReels` returning three reels. Assert `find.text('Your reels')` `findsNothing`; find the `GridView`, cast its `gridDelegate` to `SliverGridDelegateWithFixedCrossAxisCount`, and assert `crossAxisCount == 3`, `crossAxisSpacing == 2`, `mainAxisSpacing == 2`, `childAspectRatio == 0.75`. Assert three `profile-reel-*` keys are present.

Add `reel failure keeps Retry on the TikTok profile` with `loadReels` throwing once then returning one reel: assert `Could not load reels` and Retry are present, tap Retry, and assert the reel appears.

Add `TikTok profile fits a 320px screen` that pumps 320x640 with `isAdmin: true` and three reels and asserts no `FlutterError` is reported.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/profile_hub_screen_test.dart --plain-name "grid"`
Expected: FAIL because the grid still has 3px spacing, square tiles, and a section heading.

- [ ] **Step 3: Restyle the grid**

Remove the `SectionHeader(title: 'Your reels')`. Make the `ListView` padding zero and wrap only the header children in `Padding`. Keep the loading, error-with-Retry, and empty states unchanged. Set the grid delegate to the values in Interfaces and keep the existing `profile-reel-*` keys and tap behavior.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/profile_hub_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Full verification and commit**

Run: `flutter analyze` then `flutter test`.
Expected: no new analyzer errors; all tests pass.

```bash
git add lib/screens/profile_hub_screen.dart test/profile_hub_screen_test.dart
git commit -m "feat(ui): edge-to-edge TikTok reel grid on own profile"
```
