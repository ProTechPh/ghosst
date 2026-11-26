# Ghosst Social-first App Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current six/seven-tab Ghosst shell with a TikTok-inspired five-tab social-first app: Reels home, Shop dashboard, Create action, unified Inbox, and Profile dashboard.

**Architecture:** Keep all existing business services and backend contracts. Introduce a small social UI component layer, migrate `HomeShell` to an enum-driven five-tab shell, then build Shop/Profile hubs and refine Reels/Inbox. Secondary screens keep their logic and receive the new visual system.

**Tech Stack:** Flutter/Dart, Material 3, existing `cached_network_image`, `share_plus`, `dio`, Firebase chat, PHP/MySQL API.

**Spec:** `docs/superpowers/specs/2026-11-26-tiktok-style-app-redesign-design.md` (approved 2026-11-26).

## Global Constraints

- UI-only redesign: no backend endpoints, schema, auth, ads, claims, downloads, or social-rule changes.
- Reels is the default home screen and remains image-only carousels.
- Exactly five navigation destinations: Home, Shop, Create, Inbox, Profile.
- Hybrid palette: canvas `#0B0F12`, surface `#171D23`, surface high `#26323B`, text `#F8FAFC`, muted `#8B98A5`, cyan `#22D3EE`, cyan deep `#0E7490`, gold `#FBBF24`, red `#F43F5E`.
- Inbox contains World chat and DMs only; no activity notifications/history.
- Profile is read-only; no Edit profile button or bio update endpoint.
- Admin entry is admins-only.
- Share is an app/website invite, not a profile/reel deep link.
- Keep Space Grotesk and JetBrains Mono.
- Minimum touch target 48dp; WCAG 2.2 AA contrast and semantics.
- Preserve `IndexedStack` state and existing callback-based secondary navigation.
- Do not manually bump build number, push, merge, or deploy without owner approval.

## Review Focus

1. Create tab changes the selected page or fires an interstitial → Task 2 verifies Create only calls `onCreate`; Task 3 verifies it never changes `SocialTab`.
2. Old integer tab indexes remain and open the wrong screen → Task 3 replaces all tab state with `SocialTab` and removes `ProfileScreen.onGoToTab`.
3. Non-admin users see Admin → Task 6 verifies the Admin chip is absent unless `isAdmin` is true.
4. Public World chat and private DMs are mixed or mislabeled → Task 5 verifies distinct World chat card and DM list.
5. Global AppBar/banners obscure full-screen Reels → Task 3 verifies Home has no shell chrome; Task 5 verifies Reels owns its top controls.
6. Share sends a nonexistent profile URL → Task 6 verifies Share invokes the injected app-invite callback and no profile route is opened.

---

### Task 1: Hybrid theme tokens and shared primitives

**Files:**
- Modify: `lib/theme.dart`
- Modify: `lib/premium.dart`
- Modify: `test/theme_test.dart`

**Interfaces:**
- Consumes: existing `AppColors`, `AppTheme`, `CoinPill`, `GlowCard`, `NeonButton`, `EmptyState`, `SectionHeader`.
- Produces: Hybrid palette and solid-black navigation theme used by every later task.

- [ ] **Step 1: Update the failing theme assertions**

In `test/theme_test.dart`, assert:

```dart
expect(AppColors.bg, const Color(0xFF0B0F12));
expect(AppColors.surface, const Color(0xFF171D23));
expect(AppColors.surfaceHigh, const Color(0xFF26323B));
expect(AppColors.primary, const Color(0xFF22D3EE));
expect(AppColors.gold, const Color(0xFFFBBF24));
expect(AppColors.red, const Color(0xFFF43F5E));
expect(AppTheme.dark.navigationBarTheme.backgroundColor, Colors.black);
expect(AppTheme.dark.navigationBarTheme.height, 64);
expect(_contrast(AppColors.text, AppColors.bg), greaterThanOrEqualTo(4.5));
expect(_contrast(AppColors.textDim, AppColors.surface), greaterThanOrEqualTo(4.5));
```

Define `_contrast(Color a, Color b)` in the test using the WCAG relative-luminance formula.

Run: `flutter test test/theme_test.dart`
Expected: FAIL on old token values.

- [ ] **Step 2: Implement the Hybrid tokens**

Update `AppColors` to the exact spec values. Keep `cyan`, `green`, `text`, and `textDim` meaningful; set `textDim` to `#8B98A5`. Update `AppTheme.dark` navigation bar to solid black, 64dp height, no pill indicator, cyan selected icons.

- [ ] **Step 3: Tone down shared surfaces**

In `lib/premium.dart` and `lib/theme.dart`, reduce excessive neon shadows/borders on `GlowCard`, `NeonButton`, and `CoinPill`. Keep gold coin emphasis and red error/like semantics. Do not change component signatures.

- [ ] **Step 4: Run theme tests**

Run: `flutter test test/theme_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/theme.dart lib/premium.dart test/theme_test.dart
git commit -m "feat(ui): adopt hybrid social-first design tokens"
```

### Task 2: Social shell components

**Files:**
- Create: `lib/social_shell.dart`
- Create: `test/social_shell_test.dart`

**Interfaces:**
- Produces:
  - `enum SocialTab { home, shop, create, inbox, profile }`
  - `extension SocialTabPage on SocialTab { int get pageIndex; }` where home=0, shop=1, inbox=2, profile=3, create=-1.
  - `class FiveTabBar extends StatelessWidget`
  - `FiveTabBar({required SocialTab selected, required ValueChanged<SocialTab> onSelected, required VoidCallback onCreate, Map<SocialTab, int> unread = const {}})`
  - `class SocialAppBar extends StatelessWidget implements PreferredSizeWidget`
  - `SocialAppBar({required String title, List<Widget> actions = const []})`

- [ ] **Step 1: Write failing component tests**

Assert five visible labels in order: Home, Shop, Create, Inbox, Profile. Assert selected semantics, 48dp minimum targets, Inbox unread badge, and that tapping Create calls only `onCreate` while `onSelected` remains untouched. Pump `SocialAppBar(title: 'Wallet')` and assert transparent/black background, white title, and `kToolbarHeight` preferred size.

Run: `flutter test test/social_shell_test.dart`
Expected: FAIL because `social_shell.dart` is absent.

- [ ] **Step 2: Implement `SocialTab` and `pageIndex`**

Create the enum and extension in `lib/social_shell.dart`. `create.pageIndex` returns `-1`; it is an action, not a page.

- [ ] **Step 3: Implement `FiveTabBar`**

Use a solid black `Container` with `SafeArea`, five equal slots, cyan selected state, and the center white create pill with cyan offset accents. The create slot must have `Semantics(button: true, label: 'Create reel')`.

- [ ] **Step 4: Implement `SocialAppBar`**

Return a transparent `AppBar` with `AppColors.text` foreground, no elevation/surface tint, left-aligned title, and caller-provided actions. `preferredSize` is `Size.fromHeight(kToolbarHeight)`.

- [ ] **Step 5: Run component tests**

Run: `flutter test test/social_shell_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/social_shell.dart test/social_shell_test.dart
git commit -m "feat(ui): add social navigation and app bar"
```

### Task 3: HomeShell migration and secondary routes

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/screens/profile_screen.dart`
- Create: `lib/screens/profile_hub_screen.dart`
- Create: `test/home_shell_navigation_test.dart`

**Interfaces:**
- Consumes: `SocialTab`, `FiveTabBar` from Task 2.
- Produces:
  - `HomeShell.tab` is `SocialTab`, default `SocialTab.home`.
  - `ProfileScreen` replaces `onGoToTab(int)` with `VoidCallback? onOpenKeys`.
  - Placeholder `ProfileHubScreen` with this final constructor:

```dart
ProfileHubScreen({
  required String userId,
  required String displayName,
  String? avatarUrl,
  required bool isAdmin,
  required VoidCallback onOpenKeys,
  required VoidCallback onOpenWallet,
  required VoidCallback onOpenFeedback,
  required VoidCallback onOpenAdmin,
  required VoidCallback onOpenSettings,
  required VoidCallback onShare,
  Future<PublicUser> Function(String id)? loadProfile,
  Future<List<Reel>> Function(String id, int offset)? loadReels,
  ValueChanged<Reel>? onOpenReel,
})
```

  - `_openStore()`, `_openEarn()`, `_openKeys()`, `_openTutorials()`, `_openWorldChat()`, `_openProfileSettings()`, `_openFeedback()` route helpers.

- [ ] **Step 1: Write failing navigation tests**

Test `SocialTab.pageIndex` for all values. Test `FiveTabBar` integration through a small harness: selecting Inbox updates selected state; Create invokes upload callback without changing selected state. Add a source-level regression check that `main.dart` contains no `tab = [0-9]` assignments.

Run: `flutter test test/home_shell_navigation_test.dart`
Expected: FAIL before enum migration.

- [ ] **Step 2: Replace integer tab state**

In `HomeShell`, change `int tab` to `SocialTab tab = SocialTab.home`. Replace all numeric assignments with enum values. Use `tab.pageIndex` for `IndexedStack`. Remove the old `_GlassNavBar`, `_NavItem`, and global AppBar.

- [ ] **Step 3: Build the four-page stack**

Pages, in order:

1. Existing `ReelsScreen(active: tab == SocialTab.home, onOpenProfile: _openUserProfile, onDeleteReel: Backend.deleteReel)`.
2. Existing `StoreScreen(coins: coins, onRefresh: _refresh, onOpenWallet: _openWallet, onGoToEarn: _openEarn)` as the temporary Shop page.
3. Existing `InboxScreen(onOpenThread: (thread, peer) => _openDirectChat(peerId: peer.id, peerName: peer.name, peerAvatarUrl: peer.avatarUrl))`; embedded mode arrives in Task 5.
4. `ProfileHubScreen(userId: Backend.cachedUser?.id ?? '', displayName: display, avatarUrl: photoUrl, isAdmin: isAdmin, onOpenKeys: _openKeys, onOpenWallet: _openWallet, onOpenFeedback: _openFeedback, onOpenAdmin: () {}, onOpenSettings: _openProfileSettings, onShare: () {}, onOpenReel: _openCreatorReel)` with a simple avatar/name and “Account settings” button.

`FiveTabBar` receives `selected: tab`, `onSelected`, `onCreate: _openReelUpload`, and `unread: {if (_chatUnread > 0) SocialTab.inbox: _chatUnread}`.

- [ ] **Step 4: Move secondary screens behind routes and clean settings callbacks**

Implement route helpers with the existing constructors:

- `_openStore()` pushes `StoreScreen(coins: coins, onRefresh: _refresh, onOpenWallet: _openWallet, onGoToEarn: _openEarn)`.
- `_openEarn()` pushes `EarnScreen(coins: coins, onRefresh: _refresh)`.
- `_openKeys()` pushes `MyKeysScreen(onGoToStore: _openStore)`.
- `_openTutorials()` pushes `TutorialsScreen(embedded: false)`.
- `_openWorldChat()` pushes `ChatScreen(embedded: false, isAdmin: isAdmin, isModerator: isModerator, onOpenInbox: () => setState(() => tab = SocialTab.inbox), onOpenProfile: _openUserProfile)`.
- `_openProfileSettings()` pushes `ProfileScreen(onSignOut: widget.onSignOut, onAccountDeleted: widget.onSignOut, onOpenKeys: _openKeys)`.
- `_openFeedback()` pushes `FeedbackScreen()`.

In `ProfileScreen`, replace `onGoToTab(int)` with `onOpenKeys()` and call it from the purchases/keys action. Change `_openWallet()` so `onGoToEarn` calls `_openEarn()`. Change `_openInbox()` to select `SocialTab.inbox`. Change `_openProfile()` to select `SocialTab.profile`. After successful reel upload, select `SocialTab.home`.

- [ ] **Step 5: Scope shell chrome**

Remove `ArcadeBackdrop` and the global AppBar. Render `AnnouncementBanner` and banner ad only when `tab` is Shop, Inbox, or Profile; Home/Reels remains edge-to-edge. Keep interstitial cadence, but Create must not count as a tab switch.

- [ ] **Step 6: Run navigation tests**

Run: `flutter test test/home_shell_navigation_test.dart test/social_shell_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/main.dart lib/screens/profile_screen.dart lib/screens/profile_hub_screen.dart test/home_shell_navigation_test.dart
git commit -m "feat(ui): migrate home shell to five social tabs"
```

### Task 4: Shop dashboard

**Files:**
- Create: `lib/screens/shop_hub_screen.dart`
- Modify: `lib/main.dart`
- Create: `test/shop_hub_screen_test.dart`

**Interfaces:**
- Consumes: `Product`, `Claim`, `Backend.products()`, `Backend.myClaims()`.
- Produces:

```dart
ShopHubScreen({
  required int coins,
  required Future<void> Function() onRefresh,
  required VoidCallback onOpenEarn,
  required VoidCallback onOpenStore,
  required VoidCallback onOpenKeys,
  required VoidCallback onOpenTutorials,
  required VoidCallback onOpenWallet,
  Future<List<Product>> Function()? loadProducts,
  Future<List<Claim>> Function()? loadClaims,
})
```

- [ ] **Step 1: Write failing dashboard tests**

Inject two products and two claims. Assert coin balance, Earn coins, Browse store, Your keys, featured product names, Tutorials, and Wallet entry. Assert every action invokes its callback. Assert product failure keeps the rest of the dashboard usable.

Run: `flutter test test/shop_hub_screen_test.dart`
Expected: FAIL on placeholder screen.

- [ ] **Step 2: Implement dashboard loading**

Load products and claims in parallel. Coins come from the shell. Show a compact loading state for shelves; never block the coin hero or primary actions on product fetch failure.

- [ ] **Step 3: Implement dashboard layout**

Use the approved Hybrid dashboard: coin hero, two primary actions, keys preview, featured grid, and secondary Tutorials/Wallet links. Reuse `CoinPill`, `SectionHeader`, `GlowCard`, and `EmptyState`.

- [ ] **Step 4: Replace the temporary Shop page**

In `HomeShell`, replace `StoreScreen` in the `IndexedStack` with `ShopHubScreen(coins: coins, onRefresh: _refresh, onOpenEarn: _openEarn, onOpenStore: _openStore, onOpenKeys: _openKeys, onOpenTutorials: _openTutorials, onOpenWallet: _openWallet)`.

- [ ] **Step 5: Run dashboard tests**

Run: `flutter test test/shop_hub_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/shop_hub_screen.dart lib/main.dart test/shop_hub_screen_test.dart
git commit -m "feat(ui): build shop dashboard hub"
```

### Task 5: Reels home and unified Inbox

**Files:**
- Modify: `lib/screens/reels_screen.dart`
- Modify: `lib/screens/inbox_screen.dart`
- Modify: `lib/main.dart`
- Modify: `test/reels_screen_test.dart`
- Modify: `test/direct_chat_inbox_test.dart`

**Interfaces:**
- Produces:
  - `ReelsScreen` gains `int coins = 0` and `VoidCallback? onOpenWallet`; embedded Home shows a top-right `CoinPill` and no floating upload FAB.
  - `InboxScreen` gains `bool embedded = false`, `VoidCallback? onOpenWorldChat`, and `ValueChanged<int>? onUnreadChanged`; embedded mode hides its outer AppBar chrome and shows a pinned World chat card.

- [ ] **Step 1: Write failing Reels tests**

Assert embedded Reels shows the coin balance, tapping it calls `onOpenWallet`, and no `Upload reel` FAB is present. Assert carousel dots expose semantics such as `Image 1 of 3` and selected state. Keep existing feed/carousel/action tests.

Run: `flutter test test/reels_screen_test.dart`
Expected: FAIL on missing coin/wallet behavior.

- [ ] **Step 2: Implement Reels home chrome**

Add the coin pill to the embedded top row. Remove the floating upload button from embedded mode; Create is now the only upload entry point. Add `Semantics(label: 'Image ${image.position} of ${images.length}', selected: i == _index)` to each carousel dot. Preserve standalone creator-reel mode.

- [ ] **Step 3: Write failing Inbox tests**

Assert a visible `World chat` card appears above the DM list, calls `onOpenWorldChat`, and embedded mode has no duplicate Inbox AppBar. Assert DM rows still open private threads and `onUnreadChanged` receives the number of unread threads.

Run: `flutter test test/direct_chat_inbox_test.dart`
Expected: FAIL on missing World chat card/embedded mode.

- [ ] **Step 4: Implement unified Inbox**

Add the World chat card and embedded flag. Keep DMs and unread state unchanged. Report the unread-thread total through `onUnreadChanged`. Do not add activity notifications. In `HomeShell`, pass `embedded: true`, `coins`, and `onOpenWallet` to Reels; pass `embedded: true`, `onOpenWorldChat`, and `onUnreadChanged` to Inbox.

- [ ] **Step 5: Run both suites**

Run: `flutter test test/reels_screen_test.dart test/direct_chat_inbox_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/reels_screen.dart lib/screens/inbox_screen.dart lib/main.dart test/reels_screen_test.dart test/direct_chat_inbox_test.dart
git commit -m "feat(ui): finish reels home and unified inbox"
```

### Task 6: Profile dashboard

**Files:**
- Modify: `lib/screens/profile_hub_screen.dart`
- Modify: `lib/main.dart`
- Create: `test/profile_hub_screen_test.dart`
- Modify: `test/user_profile_screen_test.dart` only if shared visuals require it.

**Interfaces:**
- Produces:

```dart
ProfileHubScreen({
  required String userId,
  required String displayName,
  String? avatarUrl,
  required bool isAdmin,
  required VoidCallback onOpenKeys,
  required VoidCallback onOpenWallet,
  required VoidCallback onOpenFeedback,
  required VoidCallback onOpenAdmin,
  required VoidCallback onOpenSettings,
  required VoidCallback onShare,
  Future<PublicUser> Function(String id)? loadProfile,
  Future<List<Reel>> Function(String id, int offset)? loadReels,
  ValueChanged<Reel>? onOpenReel,
})
```

- [ ] **Step 1: Write failing profile tests**

Inject a public profile and two reels. Assert display name, handle, stats, static tagline, Keys/Wallet/Feedback actions, reel grid, Settings, and Share. Assert Admin appears only when `isAdmin` is true. Assert Share calls `onShare` and no navigation callback.

Run: `flutter test test/profile_hub_screen_test.dart`
Expected: FAIL on placeholder screen.

- [ ] **Step 2: Implement read-only profile dashboard**

Load public profile and reels through injected functions. Show the static tagline; do not render Edit profile. Add quick-action chips and reel grid. Admin chip is conditional on `isAdmin`.

- [ ] **Step 3: Wire profile actions and sharing**

In `HomeShell`, replace the Task 3 no-op callbacks with `_openKeys`, `_openWallet`, `_openFeedback`, `_openAdmin`, `_openProfileSettings`, and `_shareApp`. Implement `_openAdmin()` as a route wrapping `AdminScreen(onAnnouncementSent: _refresh)` in `Scaffold(appBar: SocialAppBar(title: 'Admin'), body: AdminScreen(onAnnouncementSent: _refresh))`; Task 8 moves that wrapper into `AdminScreen`. Implement `_shareApp()` using `Share.share` with the Play Store URL for Play builds and `https://ghossthub.com` for Direct.

- [ ] **Step 4: Run profile tests**

Run: `flutter test test/profile_hub_screen_test.dart test/user_profile_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/profile_hub_screen.dart lib/main.dart test/profile_hub_screen_test.dart test/user_profile_screen_test.dart
git commit -m "feat(ui): build read-only profile dashboard"
```

### Task 7: Store, Earn, Keys, and Tutorials visual pass

**Files:**
- Modify: `lib/screens/store_screen.dart`
- Modify: `lib/screens/earn_screen.dart`
- Modify: `lib/screens/my_keys_screen.dart`
- Modify: `lib/screens/tutorials_screen.dart`
- Modify: `test/tutorials_screen_test.dart`
- Create: `test/commerce_screens_test.dart`

**Interfaces:**
- Consumes: Hybrid theme, `SocialAppBar`, and shared primitives from Tasks 1–2.
- Produces: visually consistent secondary commerce screens with unchanged business callbacks.

- [ ] **Step 1: Write failing visual/navigation smoke tests**

Pump each screen with existing injected/default paths where possible. Assert black/white surface hierarchy, visible section headers, and preserved primary actions. For Store and Keys, assert empty/error states remain reachable.

Run: `flutter test test/commerce_screens_test.dart test/tutorials_screen_test.dart`
Expected: FAIL on old decorative headers/surfaces.

- [ ] **Step 2: Apply the visual system**

Replace dominant `MeshBackground`/`TableSurface` usage on these screens with `AppColors.bg` and solid `AppColors.surface` cards. Use `SocialAppBar`, `SectionHeader`, consistent 12–16px radii, and restrained cyan/gold accents. Preserve all ad, purchase, claim, and tutorial logic.

- [ ] **Step 3: Run tests**

Run: `flutter test test/commerce_screens_test.dart test/tutorials_screen_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/store_screen.dart lib/screens/earn_screen.dart lib/screens/my_keys_screen.dart lib/screens/tutorials_screen.dart test/commerce_screens_test.dart test/tutorials_screen_test.dart
git commit -m "feat(ui): restyle commerce and tutorial screens"
```

### Task 8: Account and admin screens visual pass

**Files:**
- Modify: `lib/screens/wallet_screen.dart`
- Modify: `lib/screens/feedback_screen.dart`
- Modify: `lib/screens/admin_screen.dart`
- Modify: `lib/screens/profile_screen.dart`
- Modify: `test/feedback_screen_test.dart`
- Create: `test/account_screens_test.dart`

**Interfaces:**
- Consumes: Hybrid theme, `SocialAppBar`, `SectionHeader`, `GlowCard`, `EmptyState`.
- Produces: consistent account/admin surfaces without behavior changes; `AdminScreen` is a route screen with its own `Scaffold` and `SocialAppBar`.

- [ ] **Step 1: Write failing smoke assertions**

In `test/account_screens_test.dart`, pump `WalletScreen`, `ProfileScreen`, and `AdminScreen` with no-op callbacks where required. Assert visible `SocialAppBar` titles, `AppColors.bg` scaffold backgrounds, and no `MeshBackground`/`TableSurface` on these screens. Keep existing feedback validation/history assertions.

Run: `flutter test test/account_screens_test.dart test/feedback_screen_test.dart`
Expected: FAIL on old headers/surfaces or missing Admin route scaffold.

- [ ] **Step 2: Apply the visual system**

Use `SocialAppBar`, solid dark surfaces, consistent cards, and restrained accents. Move the Task 6 route wrapper into `AdminScreen` so it owns its `Scaffold` and `SocialAppBar`; remove its tab-only `active` behavior if no longer used. Preserve admin authorization, account deletion, feedback privacy, wallet history, and settings behavior.

- [ ] **Step 3: Run tests**

Run: `flutter test test/account_screens_test.dart test/feedback_screen_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/wallet_screen.dart lib/screens/feedback_screen.dart lib/screens/admin_screen.dart lib/screens/profile_screen.dart test/account_screens_test.dart test/feedback_screen_test.dart
git commit -m "feat(ui): restyle account and admin screens"
```

### Task 9: Detail and chat screens visual pass

**Files:**
- Modify: `lib/screens/product_detail.dart`
- Modify: `lib/screens/claim_reveal.dart`
- Modify: `lib/screens/download_screen.dart`
- Modify: `lib/screens/chat_screen.dart`
- Modify: `lib/screens/direct_chat_screen.dart`
- Modify: `test/claim_reveal_test.dart`
- Modify: `test/chat_screen_test.dart`
- Modify: `test/direct_chat_screen_test.dart`
- Modify: `test/screens_smoke_test.dart`

**Interfaces:**
- Consumes: Hybrid theme, `SocialAppBar`, shared cards and buttons.
- Produces: visually consistent detail/chat screens with unchanged safety and purchase behavior.

- [ ] **Step 1: Write failing smoke assertions**

Extend `screens_smoke_test.dart` with a `ProductDetailScreen` pump that asserts the product title and black scaffold. Extend detail/chat tests to assert white `SocialAppBar` titles and 48dp primary actions. Keep existing claim, download, chat, and DM behavior assertions.

Run: `flutter test test/claim_reveal_test.dart test/chat_screen_test.dart test/direct_chat_screen_test.dart test/screens_smoke_test.dart`
Expected: FAIL where old surfaces remain.

- [ ] **Step 2: Apply the visual system**

Use solid dark surfaces, `SocialAppBar`, consistent cards, and restrained cyan/gold/red accents. Preserve claim reveal, download, chat moderation, blocking, reporting, and message privacy logic.

- [ ] **Step 3: Run tests**

Run: `flutter test test/claim_reveal_test.dart test/chat_screen_test.dart test/direct_chat_screen_test.dart test/screens_smoke_test.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/product_detail.dart lib/screens/claim_reveal.dart lib/screens/download_screen.dart lib/screens/chat_screen.dart lib/screens/direct_chat_screen.dart test/claim_reveal_test.dart test/chat_screen_test.dart test/direct_chat_screen_test.dart test/screens_smoke_test.dart
git commit -m "feat(ui): restyle detail and chat screens"
```

### Task 10: Cleanup, documentation, and full verification

**Files:**
- Modify: `lib/main.dart`
- Modify: `SETUP.md` only if it documents bottom navigation.
- Modify: `test/home_shell_navigation_test.dart`
- Modify: `docs/superpowers/specs/2026-11-26-tiktok-style-app-redesign-design.md` only for implementation notes.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: release-ready redesigned app with no obsolete navigation paths.

- [ ] **Step 1: Remove obsolete code**

Delete unused `_GlassNavBar`, `_NavItem`, integer tab callbacks, duplicate upload FAB wiring, and imports made obsolete by the migration. Ensure no `tab = [0-9]` assignments remain.

- [ ] **Step 2: Update navigation docs**

If `SETUP.md` describes the tab bar, update it to Home/Shop/Create/Inbox/Profile and note that Store/Earn/Keys/Tutorials live behind Shop.

- [ ] **Step 3: Run focused regression suites**

Run:

```bash
flutter test test/theme_test.dart test/social_shell_test.dart test/home_shell_navigation_test.dart test/shop_hub_screen_test.dart test/reels_screen_test.dart test/direct_chat_inbox_test.dart test/profile_hub_screen_test.dart test/commerce_screens_test.dart test/account_screens_test.dart test/screens_smoke_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run full Flutter gates**

Run: `flutter analyze`
Expected: no issues.

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 5: Verify reduced-motion behavior**

Pump `FiveTabBar(selected: SocialTab.home, onSelected: (_) {}, onCreate: () {})` inside `MediaQuery(data: const MediaQueryData(disableAnimations: true), child: ...)` and assert navigation still works with no pending animation timers. Run: `flutter test test/social_shell_test.dart`
Expected: PASS.

- [ ] **Step 6: Build both flavors**

Run:

```bash
flutter build apk --release --flavor play
flutter build apk --release --flavor direct
```

Expected: both succeed. Use `--android-skip-build-dependency-validation` only if the known local AGP/Flutter mismatch requires it; record that in the verification notes.

- [ ] **Step 7: Device smoke test**

Verify: Reels opens first; five tabs work; Create uploads without changing tabs; Shop actions open correct routes; Inbox World chat/DMs stay separate; Profile utilities work; Admin appears only for admins; Share sends app invite; no banner/AppBar obscures Reels.

- [ ] **Step 8: Commit**

```bash
git add lib/main.dart SETUP.md test/home_shell_navigation_test.dart docs/superpowers/specs/2026-11-26-tiktok-style-app-redesign-design.md
git commit -m "chore(ui): finalize social-first app redesign"
```

Rollback: restore the commit before Task 3. No backend or database rollback is required.
