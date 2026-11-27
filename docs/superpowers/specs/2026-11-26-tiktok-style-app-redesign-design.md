# Ghosst Social-first TikTok-style App Redesign — Design

## Intent

Redesign the entire Ghosst Android app into a social-first experience inspired by TikTok’s layout and interaction patterns, while preserving Ghosst’s coin/store business and existing backend contracts.

The app opens on the Reels feed. A five-tab bottom navigation provides Home (Reels), Shop, Create, Inbox, and Profile. Store, Earn, Keys, Wallet, Feedback, Tutorials, and Admin remain reachable through the Shop and Profile hubs.

This is a full UI system change, not a Reels-only reskin.

## Goals

- Reels is the default home screen.
- Bottom navigation matches the approved TikTok-style five-tab structure.
- Hybrid visual language: black/white content-first surfaces, cyan primary actions, gold coins, red likes.
- Shop dashboard makes earning and spending coins obvious.
- Profile dashboard keeps social identity and account utilities together.
- Unified Inbox keeps World chat and DMs distinct but reachable; activity notifications are deferred.
- Profile remains read-only in this release; no bio editing endpoint is added.
- Existing backend APIs, authentication, payments/claims, ads, downloads, moderation, and account deletion continue to work.
- All primary actions remain accessible with one tap from a main tab.
- UI remains accessible, responsive, and consistent across Play and Direct flavors.

## Non-goals

- Copying TikTok’s logo, brand assets, or proprietary visual identity.
- Adding video recording or video Reels; Reels remains image-only carousels.
- Notification history/read state, profile editing, or profile/reel deep links in this release.
- Changing backend endpoints, database schema, or social rules as part of the visual redesign.
- Adding new monetization, ads, or product types.
- Exact pixel-for-pixel replication of TikTok.
- Removing existing Store/Earn/Keys/Tutorials functionality to simplify navigation.

## Anti-goals

- A social shell that hides the coin balance or makes purchasing harder.
- A full rewrite of business logic when only UI composition needs to change.
- Decorative gradients, glow effects, or motion that reduce readability or performance.
- Breaking deep links, callbacks, or state preservation between tabs.
- Shipping a redesign that only changes colors but leaves the old information architecture intact.

## Constraints

- Flutter Android app with `play` and `direct` flavors.
- Existing PHP/MySQL API and Firebase chat remain unchanged.
- Existing screens receive callbacks and use `IndexedStack`; there is no routing package.
- Network access stays in `lib/services/worker_backend.dart` and existing service classes.
- Release signing, AdMob SSV, tamper/ad-block gates, and account deletion promises remain intact.
- Tests must not require network, MySQL, Firebase, or real ad plugins.
- Do not manually bump the build number or deploy/push without owner approval.

## Approaches Considered

### 1. Social-first shell + hybrid visual system — chosen

Replace the current six/seven-tab shell with five tabs: Home, Shop, Create, Inbox, Profile. Reels becomes home. Shop and Profile become hubs for existing utilities. Apply the approved Hybrid palette and TikTok-inspired layouts across all screens.

Trade-off: largest UI change and requires careful migration of every screen, but it matches the requested whole-app direction and preserves core utility.

### 2. Visual refresh only

Keep the current navigation and screen structure, but restyle widgets with the Hybrid palette and TikTok-like components.

Trade-off: smaller and safer, but rejected because the user explicitly chose Reels as home and a five-tab social-first shell.

### 3. Social-only redesign

Redesign Reels, Chat, Inbox, and Profile, while leaving Store/Earn/Keys visually unchanged.

Trade-off: lower risk for commerce flows, but rejected because the user chose to redesign the whole app.

## Approved Information Architecture

```text
Bottom navigation
┌────────┬────────┬────────┬────────┬────────┐
│  Home  │  Shop  │   +    │ Inbox  │Profile │
│ Reels  │ Hub    │ Create │ Chats  │ Hub    │
└────────┴────────┴────────┴────────┴────────┘
```

### Home — Reels

- Vertical full-screen image-carousel feed.
- Following / For You controls at the top.
- Coin balance pill in the top-right.
- Right rail: creator avatar, like, comments, report/delete where applicable.
- Bottom caption and creator handle.
- No video playback, autoplay slideshow, or sound controls.
- Empty, error, retry, and unconfigured states remain.

### Shop — Dashboard

- Coin balance hero card with “Earn more” action.
- Two primary actions: Earn coins and Browse store.
- “Your keys” preview with direct access to the full key list.
- Featured products grid.
- Secondary entry points for Tutorials, Wallet, and product categories.
- Store, Earn, Keys, and Tutorials remain separate screens behind the hub.

### Create — Image carousel upload

- Center `+` tab opens the existing image-only Reel upload flow.
- Select 1–5 JPG/PNG/WebP images.
- Caption, upload progress, retry, and validation remain.
- No new upload backend or storage dependency.

### Inbox — Unified

- Pinned World chat card.
- Direct-message list with existing unread counts and timestamps.
- No activity feed, notification bell, or notification history in this release.
- Public World chat and private DMs remain separate destinations.

### Profile — Dashboard

- Avatar, display name, handle, existing social stats, and a static app/community tagline.
- Share action uses the system share sheet with the Ghosst app/website link; no profile deep link.
- Quick-action chips: Keys, Wallet, Feedback, Admin (Admin only for admins).
- Reel grid with direct access to the selected reel.
- Settings and account actions remain accessible from the top bar.
- Public profile viewing keeps the same social identity but hides private utilities.

## Visual System

### Palette

- Canvas: near-black `#0B0F12`
- Surface: `#171D23`
- Surface high: `#26323B`
- Text: white `#F8FAFC`
- Muted text: `#8B98A5`
- Primary action: cyan `#22D3EE`
- Primary deep: `#0E7490`
- Coins: gold `#FBBF24`
- Likes/errors: red `#F43F5E`
- Borders: `#26323B`

The existing Ghosst cyan/gold identity remains recognizable; the redesign removes excessive glow and uses color for meaning rather than decoration.

### Typography

- Keep Space Grotesk for UI and headings.
- Keep JetBrains Mono for keys, coin figures, timers, and technical values.
- Increase body readability on media overlays.
- Avoid all-caps labels except small, purposeful section markers.

### Shape and spacing

- Media remains edge-to-edge.
- Cards use 12–16px radii.
- Bottom navigation uses a solid black bar with a cyan active state.
- Create button uses the approved white pill with cyan offset accents.
- Spacing follows the existing 4/8/12/16/24/32 scale.

### Motion

- Fast 120–220ms transitions.
- No looping decorative animation.
- Respect `MediaQuery.disableAnimationsOf`.
- Media swipe and vertical feed gestures take priority over tap animations.

## Component Direction

- `SocialAppBar`: transparent/black, title left, utility icons right.
- `CoinPill`: gold coin icon and tabular figure.
- `HubCard`: reusable dashboard card for Shop and Profile.
- `QuickActionChip`: compact icon + label action.
- `ReelGrid`: three-column image grid.
- `InboxRow`: avatar, name, preview, timestamp, unread badge.
- `FiveTabBar`: Home, Shop, Create, Inbox, Profile.
- `SectionHeader`: title + optional “View all” action.

These components should be introduced only where at least two screens need the same behavior.

## Navigation and State

- Replace the current `HomeShell` tab list with five destinations.
- Keep `IndexedStack` so feed scroll, inbox state, and profile state survive tab switches.
- Move Admin out of the bottom navigation and into the Profile dashboard for authorized users.
- Move Tutorials into Shop as a secondary entry.
- Keep existing callback-based navigation for product detail, claim reveal, chat, profile, and upload screens.
- Update all hard-coded tab indexes after the shell change.
- Preserve back-stack behavior for secondary screens.

## Screen Migration Scope

The redesign touches the shell, theme, shared primitives, and all primary screens:

- `lib/main.dart`
- `lib/theme.dart`
- `lib/premium.dart`
- `lib/screens/reels_screen.dart`
- `lib/screens/store_screen.dart`
- `lib/screens/earn_screen.dart`
- `lib/screens/my_keys_screen.dart`
- `lib/screens/tutorials_screen.dart`
- `lib/screens/inbox_screen.dart`
- `lib/screens/user_profile_screen.dart`
- `lib/screens/profile_screen.dart`
- `lib/screens/wallet_screen.dart`
- `lib/screens/feedback_screen.dart`
- `lib/screens/admin_screen.dart`
- Product, claim, download, chat, and DM detail screens as needed for visual consistency.

Business services and API contracts remain unchanged.

## Accessibility

- Minimum 48dp touch targets for all icon buttons and nav items.
- White text on media requires a bottom scrim.
- Cyan/gold/red are never the only status indicator.
- Carousel dots have semantic position labels.
- Bottom navigation has selected-state semantics.
- Forms retain labels, validation, and error announcements.
- Reduced-motion mode disables nonessential animation.
- Contrast target: WCAG 2.2 AA for text and essential controls.

## Testing Strategy

- Widget tests for the five-tab shell and tab-state preservation.
- Golden-style layout tests only where stable; prefer semantic/widget assertions.
- Update existing screen tests to the new navigation and component structure.
- Keep service/model tests unchanged unless UI contracts change.
- Add tests for Admin visibility, coin balance access, and Shop/Profile quick actions.
- Run `flutter analyze`, full `flutter test`, and release build verification.

## Rollout

1. Introduce the new visual tokens and shared components.
2. Build the five-tab shell while keeping old screens temporarily reachable.
3. Migrate Home, Shop, Inbox, and Profile to approved layouts.
4. Migrate secondary screens to the same visual system.
5. Update navigation indexes, tests, and docs.
6. Run full gates and device smoke tests.
7. Remove temporary compatibility paths after verification.

Rollback: restore the previous shell/theme commit. No database or backend rollback is required.

## Acceptance Criteria

- App opens on Reels.
- Bottom navigation shows exactly Home, Shop, Create, Inbox, Profile.
- Shop dashboard shows coin balance, Earn, Store, Keys, and featured products.
- Profile dashboard shows social stats, reel grid, and admin-only utilities.
- Inbox shows World chat and DMs without mixing public/private content.
- All existing Store/Earn/Keys/Wallet/Tutorials/Feedback/Admin flows remain reachable.
- Visual system matches the approved Hybrid mockups.
- No existing service/API contract changes.
- Full Flutter test suite and analyzer pass.
- Play and Direct flavors build successfully.

## Builder Calls

- Keep existing fonts and service layer.
- Use solid black navigation rather than translucent glass.
- Introduce shared components only when reused.
- Admin appears in Profile only for admins; moderators do not receive the full Admin dashboard.
- Tutorials lives inside Shop.
- Share is an app invite, not a profile/reel deep link.
- No permanent feature flag; use a staged migration and commit-level rollback.

## Scope Decisions From Builder Check

- **Notifications:** UI-only release. World chat and DMs remain; activity notifications and read/unread history are deferred.
- **Profile editing:** Read-only. Existing display name/avatar/stats plus static tagline; no Edit profile button or update endpoint.
- **Admin access:** Admins only, matching current authorization.
- **Sharing:** System share of the app/website link. No new deep-link infrastructure.

## Implementation Notes

- The shell uses `SocialTab` plus `FiveTabBar`; the four real pages stay in an
  `IndexedStack`, while Create opens the upload route without selecting a page.
- `SocialAppBar` accepts optional `titleContent` so the DM header can keep its
  tappable peer avatar/name without duplicating app-bar styling.
- Secondary routes own their social scaffolds. Claim reveal uses a solid dark
  surface; purchase, download, moderation, blocking, reporting, and privacy
  logic remain in their existing services and handlers.
- Admin is reachable from Profile only for admins. Store/Earn/Keys/Tutorials
  remain behind Shop; Wallet/Feedback remain behind Profile.
- Backend contracts, database migrations, Firebase rules, OAuth configuration,
  and production deployment remain owner-controlled.
