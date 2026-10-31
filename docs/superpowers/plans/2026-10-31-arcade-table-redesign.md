# Arcade Table Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the store into a table of collectible cards, earning into a chip payout, and the key claim into a card reveal, using only the existing palette, fonts and motion tokens.

**Architecture:** One new file, `lib/arcade.dart`, holds every card/motion primitive (rarity rules, frame, index, table surface, chip stack, floating coin, flip, shake). The four screens consume it; no screen grows a second visual language, and `theme.dart` stays tokens.

**Tech Stack:** Flutter 3.47.6, Material 3, existing `theme.dart` / `premium.dart` primitives, `flutter_test`. No new packages, assets, audio, or backend fields.

**Spec:** `docs/superpowers/specs/2026-10-31-arcade-table-redesign-design.md`

## Global Constraints

- No new dependencies, image assets, audio, or backend fields. Rarity is derived from price at runtime.
- Only these tokens: `AppColors`, `AppText`, `AppSpace`, `AppRadius`, `kNeonGradient`, `kTealGradient`, `kGoldGradient`, `kPremiumCurve`, `kMotionFast` (240 ms), `kMotionBase` (420 ms). New durations allowed only where this plan names them: flip 720 ms, coin 900 ms, shake 380 ms, pulse 240 ms.
- Every animated widget checks `MediaQuery.disableAnimationsOf(context)` and, when true, reaches its final state without waiting and still runs its landing callback.
- Exactly two loud moments: the earn payout and the key reveal. Taps, hovers and navigation stay at the current `kMotionFast` / `kMotionBase` vocabulary.
- Copy: no `pack`, `roll`, `drop rate`, `lucky` or other loot language. Ads, coins and keys keep literal wording; the Earn CTA keeps `Watch ad` and `· +$_rewardCoins coins`.
- Do not touch: ad load/show logic, SSV, `_cooldownUntil`, the 650 ms pre-ad delay, `_verify`'s poll loop and timings, claim arithmetic, `Backend`, the native-ad block, or `GrainOverlay`.
- Out of scope: admin, profile, wallet, download, splash, landing.
- Gate after every task: `flutter analyze` (no issues) and `flutter test` (all pass; 62 existing + new).
- Widget tests do not hit the network. Test `arcade.dart` widgets directly; screen tests only where this plan injects a fake (claim flow).

## Review Focus

1. **Unknown stock must never read as empty.** `_stockOf` returns `-1` for every non-key product and for key products before stock loads. A card must show no stock label and no `SOLD OUT` in that state — only a confirmed `0` is sold out.
2. **Entry price ≠ selected price.** Duration products advertise the lowest duration cost on the shelf, while the detail page charges the selected chip. The card's rarity and price must come from `entryCost`, never from the selected duration, and must never be blank.
3. **Reduced motion must still land the reveal and its haptic.** With `disableAnimations`, the key face appears without a 720 ms wait and the haptic fires exactly once — the silent regression this plan exists to prevent.
4. **Missing metadata must not render a blank line.** An APK with no version or a file with no size still shows `APK` / `FILE`; key products show `License key`.
5. **Free or zero-price products.** `tierForCost(0)` is standard, `CardIndex` renders `0`, and nothing divides by price.

---

### Task 1: Card rules (pure functions)

**Files:**
- Create: `lib/arcade.dart`
- Test: `test/arcade_test.dart` (new)

**Interfaces:**
- Consumes: `Product`, `ProductDuration` from `lib/services/models.dart`.
- Produces: `RarityTier tierForCost(int cost)`, `int entryCost(Product p)`, `bool isSoldOutCard({required bool isKey, required int stock})`, `String cardMeta(Product p)`, `String cardType(Product p)`, `enum RarityTier { standard, plus, prime, vault }`.

- [ ] **Step 1: Write the failing tests**

```dart
Product _p({
  int cost = 100,
  String type = 'key',
  String version = '',
  String fileSize = '',
  List<ProductDuration> durations = const [],
}) => Product(
  id: 'p1',
  name: 'X',
  cost: cost,
  active: true,
  type: type,
  version: version,
  fileSize: fileSize,
  durations: durations,
);

test('tierForCost thresholds', () {
  expect(tierForCost(0), RarityTier.standard);
  expect(tierForCost(499), RarityTier.standard);
  expect(tierForCost(500), RarityTier.plus);
  expect(tierForCost(1499), RarityTier.plus);
  expect(tierForCost(1500), RarityTier.prime);
  expect(tierForCost(2999), RarityTier.prime);
  expect(tierForCost(3000), RarityTier.vault);
  expect(tierForCost(50000), RarityTier.vault);
});

test('unknown stock is not sold out', () {
  expect(isSoldOutCard(isKey: true, stock: 0), isTrue);
  expect(isSoldOutCard(isKey: true, stock: -1), isFalse); // not loaded yet
  expect(isSoldOutCard(isKey: true, stock: 3), isFalse);
  expect(isSoldOutCard(isKey: false, stock: 0), isFalse); // downloads never sell out
});

test('entryCost uses the cheapest duration', () {
  expect(entryCost(_p(cost: 900, durations: const [
    ProductDuration(label: '7d', cost: 900),
    ProductDuration(label: '30d', cost: 300),
  ])), 300);
  expect(entryCost(_p(cost: 700)), 700);
});

test('cardMeta never renders blank', () {
  expect(cardMeta(_p()), 'License key');
  expect(cardMeta(_p(type: 'apk', version: '1.2.3')), 'APK 1.2.3');
  expect(cardMeta(_p(type: 'apk')), 'APK');
  expect(cardMeta(_p(type: 'file', fileSize: '12 MB')), 'FILE · 12 MB');
  expect(cardMeta(_p(type: 'file')), 'FILE');
});

test('cardType is the index strip label', () {
  expect(cardType(_p()), 'KEY');
  expect(cardType(_p(type: 'apk')), 'APK');
  expect(cardType(_p(type: 'file')), 'FILE');
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/arcade_test.dart`
Expected: FAIL — `arcade.dart` / `tierForCost` not defined.

- [ ] **Step 3: Implement the rules in `lib/arcade.dart`**

```dart
enum RarityTier { standard, plus, prime, vault }

RarityTier tierForCost(int cost) {
  if (cost < 500) return RarityTier.standard;
  if (cost < 1500) return RarityTier.plus;
  if (cost < 3000) return RarityTier.prime;
  return RarityTier.vault;
}

/// Lowest selectable price — shelf and detail page must agree on the tier.
int entryCost(Product p) => p.hasDurations
    ? p.durations.map((d) => d.cost).reduce((a, b) => a < b ? a : b)
    : p.cost;

/// `-1` means stock is unknown (non-key product or not fetched yet).
bool isSoldOutCard({required bool isKey, required int stock}) =>
    isKey && stock == 0;

String cardMeta(Product p) { ... } // exact strings from the test
String cardType(Product p) => p.isKey ? 'KEY' : (p.isApk ? 'APK' : 'FILE');
```

Imports: `package:flutter/material.dart`, `services/models.dart`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/arcade_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/arcade.dart test/arcade_test.dart
git commit -m "feat: add arcade card rules"
```

---

### Task 2: Card surface, index strip, table weave, chip stack

**Files:**
- Modify: `lib/arcade.dart`
- Test: `test/arcade_test.dart`

**Interfaces:**
- Consumes: Task 1 rules; `AppColors`, `AppRadius`, `AppText`, `kTealGradient`, `kGoldGradient`; `groupDigits` from `premium.dart`.
- Produces:
  - `Gradient rarityEdge(RarityTier tier)`
  - `class CardFrame extends StatelessWidget { const CardFrame({super.key, required Widget child, RarityTier tier = RarityTier.standard, double radius = AppRadius.card, bool holo = false, bool glow = false}); }`
  - `class CardIndex extends StatelessWidget { const CardIndex({super.key, required int cost, required String type}); }`
  - `class TableSurface extends StatelessWidget { const TableSurface({super.key}); }`
  - `class ChipStack extends StatelessWidget { const ChipStack({super.key, int count = 3, double size = 46}); }`

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('CardFrame renders its child and the price index', (tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    home: const Scaffold(
      body: CardFrame(
        tier: RarityTier.vault,
        holo: true,
        child: CardIndex(cost: 1200, type: 'KEY'),
      ),
    ),
  ));
  expect(find.text('1,200'), findsOneWidget);
  expect(find.text('KEY'), findsOneWidget);
  expect(find.byType(CardFrame), findsOneWidget);
});

testWidgets('CardIndex renders a free price', (tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    home: const Scaffold(body: CardIndex(cost: 0, type: 'FILE')),
  ));
  expect(find.text('0'), findsOneWidget);
});

test('rarityEdge differs per tier', () {
  expect(rarityEdge(RarityTier.vault), isA<LinearGradient>());
  expect((rarityEdge(RarityTier.vault) as LinearGradient).colors,
      contains(AppColors.gold));
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/arcade_test.dart`
Expected: FAIL — `CardFrame`, `CardIndex`, `rarityEdge` undefined.

- [ ] **Step 3: Implement the four widgets**

- `rarityEdge`: standard → two `AppColors.border` colors; plus → `[AppColors.cyan.withValues(alpha: .85), AppColors.border]`; prime → `kTealGradient`; vault → `kGoldGradient`.
- `CardFrame`: outer `Container(padding: EdgeInsets.all(1), decoration: BoxDecoration(gradient: rarityEdge(tier), borderRadius: radius, boxShadow: glow ? [...])`, inner `ClipRRect(radius - 1)` → `DecoratedBox` dark gradient (`0xFF0C1C22` → `0xFF071317`) → `Stack` of `child`, optional static holo sheen (`IgnorePointer` + diagonal gold gradient at 8%, top-left → bottom-right), and `CustomPaint` corner ticks (4 L-shaped 1 px strokes, 8 px long, edge color at 35%). Holo is a **static** sheen, not a looping sweep — see Calls.
- `CardIndex`: `Row` inside a pill (`AppColors.bg` at 55% alpha, `AppRadius.pill`, horizontal 9 / vertical 5): coin icon 12 px gold, 4 px gap, `groupDigits(cost)` in `AppText.figure` at label size (11.5) gold, `Spacer`, `type` in `AppText.label` at 10 with letterSpacing 1.6, `AppColors.textDim`.
- `TableSurface`: `RepaintBoundary` → `CustomPaint` with a 28 px dot grid at alpha 0.035 and a top vignette from `AppColors.bg` 40% → transparent over the first 180 px. No animation.
- `ChipStack`: `count.clamp(3, 5)` overlapping ellipses; each 1 px gold ring (`AppColors.gold` at 45%) + dark center (`AppColors.surfaceHigh`), offset right by `size * 0.55` per chip, later chips painted over earlier. `SizedBox(width: size + step * (count - 1), height: size * 0.78, child: Stack(...))`.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/arcade_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/arcade.dart test/arcade_test.dart
git commit -m "feat: add arcade card surface, index and chips"
```

---

### Task 3: Store chase card

**Files:**
- Modify: `lib/screens/store_screen.dart` (`_featuredCard` at ~680–791, import at top, delete `_entryCost` at ~675)

**Interfaces:**
- Consumes: `CardFrame`, `CardIndex`, `tierForCost`, `entryCost`, `cardType`, `cardMeta`.
- Produces: the local `_entryCost` is deleted; every call site in this file (the chase card and, until Task 4 deletes it, `_gridCard`) uses `arcade.dart`'s `entryCost`.

- [ ] **Step 1: Wrap the poster in a rarity frame**

Replace `Pressable > ClipRRect > SizedBox(height: 286) > Stack` with `Pressable(scale: 1.01) > CardFrame(radius: AppRadius.hero, tier: tierForCost(entryCost(p))) > SizedBox(height: 286) > Stack`. `CardFrame` already clips; drop the `ClipRRect`.

- [ ] **Step 2: Add the index strip and edition label**

Inside the hero `Stack`, after the scrims, add:

```dart
Positioned(
  top: AppSpace.md, left: AppSpace.md, right: AppSpace.md,
  child: CardIndex(cost: entryCost(p), type: cardType(p)),
),
```

In the bottom `Row`, after the `Spacer()` and before the 38 px chevron circle, add (only when the card is buyable):

```dart
if (!isOwned && !soldOut) ...[
  Text(count >= 0 ? '$count left' : 'Fresh drop',
      style: AppText.label.copyWith(
          fontSize: 10, letterSpacing: 1.6, color: AppColors.textDim)),
  const SizedBox(width: AppSpace.sm),
],
```

The owned / sold-out pills, the 17 px price and the chevron stay where they are.

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: `No issues found!` (no unused `_entryCost`, no unused imports).

Run: `flutter test`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/store_screen.dart
git commit -m "feat: chase card with rarity frame and index"
```

---

### Task 4: Store card shelf

**Files:**
- Modify: `lib/screens/store_screen.dart` (`_grid` ~794–819, `_gridCard` ~821–910, `build` ~260)

**Interfaces:**
- Consumes: `CardFrame`, `CardIndex`, `TableSurface`, `isSoldOutCard`, `cardMeta`, `cardType`, `tierForCost`, `entryCost`.
- Produces: private `Widget _shelf(List<Product> items)` and `Widget _shelfCard(Product p)`; `_grid` / `_gridCard` are deleted.

- [ ] **Step 1: Put the table under the list**

Wrap the existing `RefreshIndicator` return in a `Stack`:

```dart
return Stack(
  children: [
    const Positioned.fill(child: IgnorePointer(child: TableSurface())),
    RefreshIndicator(onRefresh: _load, child: ListView(...)),
  ],
);
```

Body and scroll behavior stay identical.

- [ ] **Step 2: Replace the grid with the shelf**

`_shelf(items)` keeps today's two-column split and stagger: left column = even indices, right column = odd indices with `EdgeInsets.only(top: AppSpace.lg)` when `items.length > 1`; `AppSpace.md` gap between columns.

`_shelfCard(p)`:

```dart
final count = _stockOf(p);
final isOwned = owned.contains(p.id);
final soldOut = isSoldOutCard(isKey: p.isKey, stock: count);
final tier = tierForCost(entryCost(p));

return Pressable(
  onTap: soldOut ? null : () => _openDetail(p),
  child: CardFrame(
    tier: tier,
    holo: tier == RarityTier.vault,
    child: AspectRatio(
      aspectRatio: 5 / 7,
      child: Stack(fit: StackFit.expand, children: [
        Padding(padding: const EdgeInsets.all(10), child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card - 11),
          child: Stack(fit: StackFit.expand, children: [
            _cover(p, width: 400),
            if (soldOut) ColoredBox(color: AppColors.bg.withValues(alpha: .55)),
            // bottom scrim + name + meta
          ]),
        )),
        Positioned(top: 12, left: 12, right: 12,
            child: CardIndex(cost: entryCost(p), type: cardType(p))),
        if (isOwned) const Positioned(top: 44, right: 12, child: _OwnedSeal()),
        if (soldOut) const Center(child: _SoldOutStamp()),
      ]),
    ),
  ),
);
```

Bottom overlay inside the art (above the scrim):

```dart
Positioned(left: 10, right: 10, bottom: 10, child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: AppText.subtitle.copyWith(fontSize: 14)),
    const SizedBox(height: AppSpace.xs),
    Text(cardMeta(p), style: AppText.caption.copyWith(fontSize: 11)),
    if (!isOwned && !soldOut && count >= 0) ...[
      const SizedBox(height: 2),
      Text('$count left', style: AppText.caption.copyWith(fontSize: 11, color: AppColors.green)),
    ],
  ],
)),
```

Scrim: `LinearGradient(topCenter → bottomCenter, stops [0.45, 1], colors [bg 0%, bg 94%])` sized to the bottom 45% of the art.

`_OwnedSeal`: 22 px circle, `AppColors.cyan` 18% fill, cyan check icon 13 px.
`_SoldOutStamp`: `Container(padding: 8/4, border: 1px AppColors.textDim at 60%, radius 6)` + `Text('SOLD OUT', AppText.label.copyWith(fontSize: 10, letterSpacing: 3, color: AppColors.textDim))`, wrapped in `Transform.rotate(angle: -0.06)`.

- [ ] **Step 3: Verify**

Run: `flutter analyze`, then `flutter test`.
Expected: clean; no reference to `_grid` / `_gridCard`.

Run: `flutter run --flavor play --dart-define=USE_TEST_ADS=true` and check on a narrow phone: the 5:7 card does not overflow 2 columns at 360 dp, the name + meta fit two lines, and a non-admin sees `Fresh drop` (stock `-1`).

- [ ] **Step 4: Commit**

```bash
git add lib/screens/store_screen.dart
git commit -m "feat: store card shelf replaces the grid"
```

---

### Task 5: Flip, shake and coin motion

**Files:**
- Modify: `lib/arcade.dart`
- Test: `test/arcade_test.dart`

**Interfaces:**
- Consumes: `CardFrame`, `rarityEdge`, `LogoBadge`, `AppText`.
- Produces:
  - `class CardFlip extends StatefulWidget { const CardFlip({super.key, required Widget child, RarityTier tier = RarityTier.standard, Duration duration = const Duration(milliseconds: 720), VoidCallback? onLanded}); }`
  - `class ShakeBox extends StatefulWidget { const ShakeBox({super.key, required Widget child, bool enabled = true}); }`
  - `class FloatingCoin extends StatefulWidget { const FloatingCoin({super.key, required Offset from, required Offset to, required String label, VoidCallback? onLanded}); }`

- [ ] **Step 1: Write the failing tests**

```dart
Widget _host(Widget child, {bool reduced = false}) => MaterialApp(
  theme: AppTheme.dark,
  builder: (ctx, inner) => MediaQuery(
    data: MediaQuery.of(ctx).copyWith(disableAnimations: reduced),
    child: inner!,
  ),
  home: Scaffold(body: Center(child: child)),
);

testWidgets('CardFlip lands once after 720ms', (tester) async {
  var landed = 0;
  await tester.pumpWidget(_host(CardFlip(
    child: const Text('FACE'), onLanded: () => landed++,
  )));
  await tester.pump(const Duration(milliseconds: 700));
  expect(landed, 0);
  await tester.pump(const Duration(milliseconds: 40));
  expect(landed, 1);
  await tester.pump(const Duration(seconds: 2));
  expect(landed, 1);
});

testWidgets('CardFlip honours reduced motion and still calls back', (tester) async {
  var landed = 0;
  await tester.pumpWidget(_host(
    CardFlip(child: const Text('FACE'), onLanded: () => landed++),
    reduced: true,
  ));
  await tester.pump(); // post-frame callback
  expect(find.text('FACE'), findsOneWidget);
  expect(landed, 1);
});

testWidgets('FloatingCoin lands once at 900ms', (tester) async {
  var landed = 0;
  await tester.pumpWidget(_host(FloatingCoin(
    from: const Offset(20, 300), to: const Offset(300, 40),
    label: '+10', onLanded: () => landed++,
  )));
  await tester.pump(const Duration(milliseconds: 880));
  expect(landed, 0);
  await tester.pump(const Duration(milliseconds: 40));
  expect(landed, 1);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/arcade_test.dart`
Expected: FAIL — widgets undefined.

- [ ] **Step 3: Implement**

- `CardFlip`: `AnimationController(duration: widget.duration)`, `kPremiumCurve`. Decide reduced motion in `didChangeDependencies`: if `MediaQuery.disableAnimationsOf(context)` → mark landed, `WidgetsBinding.instance.addPostFrameCallback` → `onLanded` once. Otherwise on `AnimationStatus.completed` → `onLanded` once (one-shot guard). Rotation: `Transform(alignment: Alignment.center, transform: Matrix4.identity()..setEntry(3, 2, 0.0012)..rotateY(pi * v))`, showing the back while `v < 0.5`, and the child counter-rotated by `pi` after the halfway point so the face is not mirrored. Back: `CardFrame(tier: tier, holo: tier == RarityTier.vault)` with centered `LogoBadge(size: 64)`, `Text('GHOSST', AppText.label letterSpacing 5)` and a 1 px `rarityEdge` hairline. On landing start a 240 ms × 2 pulse (`repeat(reverse: true, count: 2)`) driving a `BoxShadow` glow at 55% of the edge color, `blurRadius 28`.
- `ShakeBox`: 380 ms controller on a damped sine — `offset = 6 * sin(value * pi * 3) * (1 - value)` px horizontal. Starts in `initState` if `enabled`; also starts in `didUpdateWidget` on `false → true`. Under `disableAnimations` it renders the child untransformed.
- `FloatingCoin`: 900 ms controller, position = quadratic bezier through a control point 90 px above the midpoint, token is a 28 px gold coin (`kGoldGradient`) with `monetization_on_rounded`, label `+10` in `AppText.figure` to its right; opacity 0→1 over the first 15%, 1→0 over the last 20%. `onLanded` once at completion. Under `disableAnimations`, paint at `to` for 200 ms and call `onLanded` at the start.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/arcade_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/arcade.dart test/arcade_test.dart
git commit -m "feat: arcade flip, shake and coin motion"
```

---

### Task 6: Claim reveal

**Files:**
- Modify: `lib/screens/claim_reveal.dart` (`_run` 115–161, `_processingView` 288–333, `_successView` 348–574, `build` 622–674)
- Test: `test/claim_reveal_test.dart` (new)

**Interfaces:**
- Consumes: `CardFlip`, `ShakeBox`, `ChipStack`, `tierForCost`, `entryCost`.
- Produces: `_landed` state on `_ClaimFlowState`, `_onFlipLanded()`.

- [ ] **Step 1: Write the failing tests**

```dart
Product _product() => Product(id: 'p1', name: 'Ghosst Pro', cost: 300, active: true);

Widget _host({required bool reduced}) => MaterialApp(
  theme: AppTheme.dark,
  builder: (ctx, inner) => MediaQuery(
    data: MediaQuery.of(ctx).copyWith(disableAnimations: reduced),
    child: inner!,
  ),
  home: Scaffold(body: Builder(builder: (ctx) => TextButton(
    onPressed: () => showClaimFlow(
      context: ctx,
      product: _product(),
      balanceBefore: 500,
      cost: 300,
      claim: () async => 'KEY-TEST-1234',
    ),
    child: const Text('go'),
  ))),
);

testWidgets('key reveal shows the key and fires one haptic', (tester) async {
  final haptics = <Object?>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  await tester.pumpWidget(_host(reduced: false));
  await tester.tap(find.text('go'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 3)); // route + 2.1s floor
  await tester.pump(const Duration(milliseconds: 760)); // flip
  expect(find.text('KEY-TEST-1234'), findsOneWidget);
  expect(haptics.length, 1);
  await tester.pump(const Duration(seconds: 2));
  expect(haptics.length, 1); // no double fire
});
```

Add a second test with `_host(reduced: true)` that pumps `3 s` after the tap plus one frame (`await tester.pump()`), then expects the key visible and `haptics.length == 1` — without the extra 760 ms the flip would take. The 3 s covers the 520 ms dialog transition and the 2.1 s floor; the extra frame lets the post-frame landing callback run.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/claim_reveal_test.dart`
Expected: FAIL — key is not found at that timing / no flip widget.

- [ ] **Step 3: Replace the 550 ms beat with the flip**

In `_run`, after `_step = 3`:

```dart
if (widget.kind != 'key') await HapticFeedback.mediumImpact();
setState(() => _phase = _Phase.success);
```

The `Future.delayed(550ms)` and the `mediumImpact()` that preceded `_phase = success` are removed. The 2.1 s floor stays.

- [ ] **Step 4: Make the key reveal a card flip**

In `_successView()`, build the existing column into a local `column`, then:

```dart
if (_isApp) {
  return ShakeBox(key: const ValueKey('app-success'), child: column);
}
return ShakeBox(
  key: const ValueKey('key-success'),
  enabled: _landed,
  child: CardFlip(
    tier: tierForCost(widget._spent ?? widget.product.cost),
    onLanded: _onFlipLanded,
    child: column,
  ),
);
```

`_onFlipLanded()` sets `_landed = true` and fires `HapticFeedback.mediumImpact()` (unawaited is fine). `_landed` resets to `false` in `_retry()`. The `CardFlip` wraps the whole success column — island, eyebrow, name, balance delta, key card and buttons — so it is the entrance and nothing is rebuilt.

- [ ] **Step 5: Suppress the switcher fade for success**

In `build`, compute `final success = _phase == _Phase.success;` and pass `duration: success ? Duration.zero : const Duration(milliseconds: 500)` to the `AnimatedSwitcher`, with `transitionBuilder: (child, anim) => success ? child : FadeTransition(...)` (keep the existing slide). The processing and failure views keep the current fade + slide.

- [ ] **Step 6: Chip motif in the processing island**

Replace the `_island(...)` call in `_processingView` with a 76 px circle (same surface, border and glow as `_island`) containing `const ChipStack(count: 3, size: 20)`. Keep `Eyebrow`, copy, and the checklist untouched.

- [ ] **Step 7: Run the tests**

Run: `flutter test test/claim_reveal_test.dart`
Expected: PASS (both reduced and full motion).

- [ ] **Step 8: Commit**

```bash
git add lib/screens/claim_reveal.dart test/claim_reveal_test.dart
git commit -m "feat: key reveal flips as a card"
```

---

### Task 7: Earn payout ceremony

**Files:**
- Modify: `lib/screens/earn_screen.dart` (imports; state 25–57; `dispose` 68–; `_verify` 225–239; `build` 282–326; `_hero` 330–428; `_primaryAction` 562–640)

**Interfaces:**
- Consumes: `ChipStack`, `TableSurface`, `FloatingCoin`.
- Produces: `final GlobalKey _ctaKey`, `OverlayEntry? _coinEntry`, `void _celebrate()`, `void _endCeremony()`.

- [ ] **Step 1: Chip tray hero + table surface**

- Wrap `build`'s `ListView` in `Stack(children: [const Positioned.fill(child: IgnorePointer(child: TableSurface())), ListView(...)])`.
- In `_hero`, add `Positioned(right: AppSpace.xl, bottom: AppSpace.xl, child: const ChipStack(count: 4, size: 42))` as the last child of the hero `Stack`.
- After the 54 px balance `FittedBox`, insert `Container(width: 54, height: 1, color: AppColors.gold.withValues(alpha: .5))` then the existing `AppSpace.sm` gap and caption.

- [ ] **Step 2: Chunkier CTA**

In `_primaryAction`, put the watch-state `Row` inside `Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(...))` so the button is ~56 px. Leave the busy and cooldown states unchanged (they already carry two rows).

- [ ] **Step 3: Fire the ceremony once, from `_verify`**

In `_verify`, inside `if (now > before)`, after `setState` sets `status = 'Coins added!'` and `_startCooldown(30)`, call `_celebrate()`. Firing from the poll branch (not from `build`) is what makes it once-per-verification.

```dart
void _celebrate() {
  if (!mounted) return;
  final overlay = Overlay.maybeOf(context);
  final box = _ctaKey.currentContext?.findRenderObject() as RenderBox?;
  if (overlay == null) return;

  final size = MediaQuery.sizeOf(context);
  var start = box != null && box.attached
      ? box.localToGlobal(box.size.center(Offset.zero))
      : Offset(size.width / 2, size.height - 160);
  if (!(Offset.zero & size).contains(start)) {
    start = Offset(size.width / 2, size.height - 160);
  }
  final end = Offset(size.width * 0.82, MediaQuery.paddingOf(context).top + 40);

  _endCeremony();
  final entry = OverlayEntry(builder: (_) => FloatingCoin(
    from: start, to: end, label: '+$_rewardCoins',
    onLanded: () {
      _coinEntry?.remove();
      _coinEntry = null;
      HapticFeedback.lightImpact();
    },
  ));
  _coinEntry = entry;
  overlay.insert(entry);
}

void _endCeremony() {
  _coinEntry?.remove();
  _coinEntry = null;
}
```

Wrap the primary CTA in `KeyedSubtree(key: _ctaKey, child: _primaryAction(...))`, call `_endCeremony()` in `dispose`, and add `import 'package:flutter/services.dart';` for `HapticFeedback`.

- [ ] **Step 4: Verify**

Run: `flutter analyze` → clean.
Run: `flutter test` → all pass.

Manual, on a device with test ads: watch one ad, confirm exactly one `+10` token arcs from the button to the app-bar coin pill, one light haptic at landing, the numeral still matches the server poll, and that returning to the tab does not replay the token.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/earn_screen.dart
git commit -m "feat: earn chip tray and coin payout ceremony"
```

---

### Task 8: Product detail frame and buy bar edge

**Files:**
- Modify: `lib/screens/product_detail.dart` (`_hero` 752–856, `_buyBar` 567–580; imports)

**Interfaces:**
- Consumes: `CardFrame`, `CardIndex`, `rarityEdge`, `tierForCost`, `entryCost`.

- [ ] **Step 1: Frame the hero**

Wrap the `SizedBox(height: 320)` returned by `_hero()` in `CardFrame(radius: 0, tier: tierForCost(entryCost(product)))`, no glow, no holo. Inside the hero `Stack`, as the last child:

```dart
Positioned(
  top: MediaQuery.paddingOf(context).top + AppSpace.sm,
  left: AppSpace.lg, right: AppSpace.lg,
  child: CardIndex(cost: entryCost(product), type: cardType(product)),
),
```

The page dots stay at the bottom; the back button is unchanged.

- [ ] **Step 2: Gradient edge on the sticky bar**

Replace the `border: Border(top: BorderSide(color: AppColors.border))` with a 1 px `Container` as the first child of the bar's inner `Column`:

```dart
Container(height: 1, decoration: BoxDecoration(
  gradient: rarityEdge(tierForCost(entryCost(widget.product))),
)),
```

Keep the `AppColors.bg` at 96% background and the `SafeArea`.

- [ ] **Step 3: Verify**

Run: `flutter analyze` → clean.
Run: `flutter test` → all pass.

Manual: open a standard, a prime and a vault-priced product; the hero edge color matches the shelf card's edge, and the buy bar edge does not shift the layout.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/product_detail.dart
git commit -m "feat: rarity frame on product detail"
```

---

### Task 9: Full gate

**Files:** none (verification only; fix in place if a gate fails).

- [ ] **Step 1: Run the gates**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: all pass — 62 existing plus the new `arcade_test.dart` and `claim_reveal_test.dart` cases.

- [ ] **Step 2: Manual pass** (needs a device; record the result in the completion note)

- A key claim: flip, key readable, one haptic, copy still works, `Done` still pops.
- An APK claim: no flip, shake, one haptic, `Download now` still pops.
- Earn: one token, one haptic, balance matches the poll.
- Store: sold-out card (stamp + dimmed art), owned card (cyan seal), non-admin (no stock line), duration product (entry price on the card).
- Product detail: frame matches the shelf tier.

- [ ] **Step 3: Commit any fix**

```bash
git add -A
git commit -m "fix: arcade table gate fixes"
```

---

## Calls made in this plan (check these)

- **Holo is a static sheen, not a looping sweep.** The spec's sweep would keep a controller running on the store's most visible card, for a detail that reads as a sheen at card size. If a real sweep is wanted later, it belongs in `CardFrame` alone.
- **The chase card presses with `scale: 1.01` and no shadow slide.** `Pressable` exposes scale only; a shadow slide would need a bespoke gesture widget for a 2 px payoff.
- **The flip wraps the whole success column.** The spec says the key card flips, then also says the flip wraps the buttons and that no success element is rebuilt. Wrapping the column is the only reading where the buttons keep working and nothing appears mid-transform.
- **The claim results stay in `_successView`; nothing is extracted into a new widget.** `CardFlip` and `ShakeBox` are wrappers, not owners.
- **Earn's ceremony state is one `OverlayEntry?` and no new flag.** Firing from `_verify` is structurally once-per-verification; there is no status listener to double-fire.
