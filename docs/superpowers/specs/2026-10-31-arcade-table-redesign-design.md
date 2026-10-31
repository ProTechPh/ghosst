# Ghosst — Arcade Table redesign

Date: 2026-10-31
Status: design, awaiting approval

## Intent

The app already has a dark-neon palette, a motion language and shared
primitives, but every screen is composed as a generic stacked card list:
identical rounded rectangles, the same vertical rhythm, nothing that makes
someone screenshot it. The user asked for a design that is not "simple" and
picked the **arcade table** direction: the store stops being a list and
becomes a table of collectible cards, earning stops being a form and becomes
a chip payout, and claiming stops being a status dialog and becomes a
reveal.

Reference points, and what is actually being taken from each:

- **Balatro** — cards are the hero surface, only numbers glow, effects are
  rationed: routine taps are quiet, the payout gets the show.
- **Steam / PlayStation mobile** — art carries the card; text is a short
  index strip, never a paragraph under the art.
- **Revolut / Robinhood** — one hero numeral, billboard scale, tabular mono.
- **Apple Design Award 2025 set** — one committed art direction per app.

## Goals

1. Store reads as a table of cards with a hierarchy (chase card → shelf),
   not a grid of equal tiles.
2. Earning has a payout ceremony: the moment coins land is visibly different
   from every other moment in the app.
3. Claiming reveals the key as a card flip, with the shake/haptic accent
   Balatro uses on a payout.
4. All of it is built from the existing palette, fonts and motion curves —
   no new packages, no new image assets, no backend change.

## Non-goals

- No new backend fields: rarity is derived from price, stock stays
  admin-only and optional.
- No changes to ad logic, SSV, cooldowns, claims, or coin arithmetic.
- No sound effects (no audio dependency exists, and adding one for this is
  not worth the APK weight).
- Admin, profile, wallet, download, splash and landing screens are out of
  scope for this pass.

## Anti-goals

- Reading as a **gacha / loot box**. Every card shows an exact price before
  the tap, the reveal is deterministic, and nothing is randomized. Rarity
  is a price tier, not a drop roll.
- Cards as decoration: if the art is cropped to a square thumbnail with a
  title underneath, the direction has failed.
- Motion on everything. Exactly two loud moments exist (payout, reveal).
  Everything else stays at the current `kMotionFast`/`kMotionBase`
  vocabulary.

## Constraints discovered in the code

- `StoreScreen` (`lib/screens/store_screen.dart`) is a `ListView` with
  `ScrollReveal` wrappers; products come from `Backend.products()`, stock is
  only populated for admins (`Backend.availableCount`), and the owned set is
  best-effort. Any card badge must degrade cleanly when stock is unknown.
- `EarnScreen` (`lib/screens/earn_screen.dart`) polls `Backend.coins()` up
  to 23 times and drives `status` strings; the ceremony has to hang off the
  existing transition to `'Coins added!'` rather than a new state machine.
  The static `_cooldownUntil`, 650 ms pre-ad delay and 30 s cooldown are
  reward-integrity code — untouched.
- `showClaimFlow` (`lib/screens/claim_reveal.dart`) already stages a fake
  2.1 s checklist before the real claim returns, then waits 550 ms and fires
  `HapticFeedback.mediumImpact()` before the success phase. The flip slots
  into that beat; the 2.1 s floor is there to make the claim feel deliberate
  and must not be removed.
- Ad disclosure: the primary Earn CTA must keep saying "Watch ad" with the
  coin value. Arcade flavor may not make the ad action ambiguous.
- No tests currently touch these screens; `test/widget_test.dart` only
  asserts the shared primitives render. Timings are pinned in splash tests,
  not here.
- `GrainOverlay` is already mounted app-wide at 3.5% opacity; keep it and do
  not stack a second grain layer.

## The direction (chosen: A — arcade table)

### Shared system — new `lib/arcade.dart`

One new file, because three screens need the same pieces. Nothing goes in
`theme.dart`; that file stays tokens and Material theming.

- `enum RarityTier { standard, plus, prime, vault }` with
  `RarityTier tierForCost(int cost)` — `< 500` standard, `< 1500` plus,
  `< 3000` prime, else vault. A product's tier is computed **once from its
  entry cost** (the lowest duration option, `_entryCost`), so the shelf and
  the detail page always agree; picking a pricier duration changes the price
  in the buy bar, not the card's frame. Frame colors: standard `AppColors.border`,
  plus `AppColors.cyan`, prime a teal→cyan gradient edge (`kTealGradient`
  reused), vault `AppColors.gold` plus a slow diagonal holo sweep at 8%
  opacity. Holo runs only on vault cards, and only while the store tab is
  visible.
- `CardFrame` — 1 px gradient edge + inner surface + corner ticks, wrapping
  arbitrary child. Variant flag `holo`.
- `CardIndex` — the top corner strip of a card: mono price with the coin
  glyph on the left, a type glyph (`KEY`/`APK`/`FILE`) on the right, both at
  `AppText.label` size. This is the Steam metadata strip, compressed.
- `TableSurface` — `CustomPainter` drawing a static 28 px dot weave plus a
  top vignette, alpha ≤ 0.035, wrapped in `RepaintBoundary`. Sits behind
  the Store and Earn lists only.
- `ChipStack` — 3–5 overlapping ellipse "chips" (gold ring, dark center)
  sized by count, used in the Earn hero and the claim success delta.
- `FloatingCoin` — a one-shot `+N` token that arcs from a start offset to an
  end offset along a quadratic bezier, 900 ms, then fades. One token, not a
  particle system.
- `CardFlip` — 3D Y-rotation (perspective 0.0012) from a card back to the
  child at 720 ms, `kPremiumCurve`; the child is swapped at 90°, edge glow
  pulses twice on landing.
- `ShakeBox` — damped sine translation, 380 ms, 6 px → 0, `Transform`
  applied to a child.

Every animated piece checks `MediaQuery.disableAnimationsOf(context)` and
falls back to a cross-fade; `CardFlip` shows its face immediately, `ShakeBox`
does nothing.

### Store (`lib/screens/store_screen.dart`)

- Keep header, shelf switch, balance hero, native ad block and refresh
  behavior exactly as they are. The mobile ad card is not restyled.
- The featured panel becomes a **chase card**: full-bleed poster stays, but
  gains a rarity frame, `CardIndex` in the top corners, and an edition label
  (`N left` when stock is known, `Fresh drop` otherwise) at the trailing end
  of the existing bottom row. The price stays at 17 px in that row; the
  index is a secondary marker, never the only place the price appears. It
  presses with a 1.01 scale and slides its shadow, not a wobble.
- `_grid`/`_gridCard` are replaced by a **card shelf**: two columns, card
  ratio 5:7, art inset 10 px inside the frame, name over the bottom of the
  art behind a scrim, `CardIndex` on top, and a sold-out treatment that
  dims the art and stamps `SOLD OUT` in label caps across the card. Owned
  cards get a small cyan check seal, not a full-width pill. The version /
  file-size line and `N left` (when stock is known) keep their place as a
  small meta line under the name — no information the current card shows is
  dropped.
- Cards keep the `Pressable` tap behavior and stagger (`AppSpace.lg` offset
  on the right column) so the shelf still reads as editorial.
- Do not pull the native-ad lazy-load logic apart. Only the card widgets
  change.

### Earn (`lib/screens/earn_screen.dart`)

- Hero becomes a **chip tray**: `ChipStack` bottom-right, balance numeral
  unchanged at 54 px (it is already the hero), a thin gold hairline under
  the numeral, and the `LIVE` pill kept.
- The stats row stays (cooldown / verification). It is information, not
  decoration.
- Payout ceremony: when `status` becomes `'Coins added!'`, play
  `FloatingCoin` (`+10`) from the CTA to the fixed app-bar `CoinPill`, and
  fire one `HapticFeedback.lightImpact()` when it lands. It is inserted as
  an `OverlayEntry` (not inside the scroll view) so the arc is visible even
  when the hero has scrolled away; the app bar is always on screen, so the
  target is `Offset(screenWidth * 0.82, safeTop + 40)` rather than a
  `GlobalKey` into another widget. No shake here — the shake is reserved for
  the key reveal. The ceremony must be idempotent: it fires once per
  successful verification, not on rebuild.
- Primary CTA keeps the "Watch ad · +10 coins" string and the cooldown
  progress bar. The button becomes a taller, chunkier `NeonButton` (56 px)
  with the coin value in mono; the outline "Instant ad" button stays
  secondary.

### Claim reveal (`lib/screens/claim_reveal.dart`)

- Processing view is unchanged except the island icon is replaced by a
  small chip-stack motif — the checklist is good and should not be touched.
- Success view, `kind == 'key'`: the key card enters via `CardFlip` from a
  drawn card back (rarity frame, Ghosst emblem, diagonal weave), lands with
  two gold pulses, then `ShakeBox` plays 380 ms. The flip **replaces** the
  current 550 ms hold: `_run` goes `_step = 3` → `_phase = success` at the
  2.1 s floor, the success column is suppressed from the `AnimatedSwitcher`
  fade/slide (a flat keyed transition for this phase only) and the flip is
  the entrance. Net time to a readable key is ~720 ms instead of 550 + 500,
  so nothing gets slower.
- The `HapticFeedback.mediumImpact()` in `_run` moves into the flip's
  landing callback, at 720 ms. In the reduced-motion path the face is shown
  immediately and the same haptic fires at once — the regression is silent
  if that branch is forgotten, so it gets a test.
- `kind == 'app'` skips the flip: there is no object to reveal, and the
  payoff is the download route itself. It keeps the current fade, gains the
  380 ms shake on landing, and keeps the haptic. No new copy or new card
  surface is invented for it.
- Key typography, copy button, `COPIED` state, and the `Done`/`Download now`
  buttons stay byte-for-byte in behavior. The flip wraps them; it does not
  rebuild them.
- Failure view is unchanged.

### Product detail (`lib/screens/product_detail.dart`)

- Smallest possible touch: the hero gets the same rarity hairline frame and
  a `CardIndex` overlay; the sticky buy bar gets a 1 px gradient top edge.
  No layout change, no new controls.

## Files touched

| File | Change |
|---|---|
| `lib/arcade.dart` | new — tier, frame, index, table, chip, coin, flip, shake |
| `lib/screens/store_screen.dart` | chase card + card shelf |
| `lib/screens/earn_screen.dart` | chip tray + payout ceremony |
| `lib/screens/claim_reveal.dart` | flip + shake on success |
| `lib/screens/product_detail.dart` | frame + index on hero |
| `test/arcade_test.dart` | new — tier thresholds, frame/index render, reduced-motion path |

## Testing

- `test/arcade_test.dart`: `tierForCost` at the boundaries (499/500,
  1499/1500, 2999/3000); `CardFrame` renders its child and a price index;
  `CardFlip` with `disableAnimations` shows the face without pumping 720 ms
  and still calls its landing callback (the haptic hook).
- Manual: claim a key and an APK, verify the flip and that the haptic still
  fires; earn a reward and confirm the ceremony fires once and the balance
  numeral still matches the server poll; check a sold-out and an owned card.
- Gate: `flutter analyze`, `flutter test` (62 existing + new).

## Risks

- **Gacha optics.** Cards plus rarity plus a reveal is one step from loot
  boxes. Mitigation is structural: price on every card, no randomness, no
  "pack" language in the copy, ad CTA wording unchanged. If it still reads
  as gambling, the fallback is to drop the rarity frame and keep the card
  geometry — a one-file change in `arcade.dart`.
- **Low-end phones.** Static painters and one animation controller at a
  time (never the coin and the flip together) keep the cost bounded;
  `RepaintBoundary` on `TableSurface` and the card art.
- **Scope creep by taste.** The temptation is to restyle wallet, profile
  and download in the same pass. Resist; this pass is the three surfaces
  that define the direction.

## Calls made by the builder (not the user)

- Ratio 5:7 over 1:1 or 16:9: 1:1 is what makes the current grid generic,
  and 16:9 wastes vertical space on a phone.
- Rarity names Standard / Plus / Prime / Vault instead of
  common/rare/legendary, to keep distance from loot language.
- No tilt/parallax on every card — only the chase card presses with a
  shadow slide. Tracking pointers on every tile is the kind of motion that
  makes a cheap phone stutter.
- Copy: arcade voice only in decorative labels (`Vault`, `Fresh drop`);
  anything involving ads, coins or keys keeps its literal wording.
