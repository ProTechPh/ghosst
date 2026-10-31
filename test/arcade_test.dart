import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/arcade.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

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

void main() {
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
    expect(
      isSoldOutCard(isKey: false, stock: 0),
      isFalse,
    ); // downloads never sell out
  });

  test('entryCost uses the cheapest duration', () {
    expect(
      entryCost(
        _p(
          cost: 900,
          durations: const [
            ProductDuration(label: '7d', cost: 900),
            ProductDuration(label: '30d', cost: 300),
          ],
        ),
      ),
      300,
    );
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

  testWidgets('CardFrame renders its child and the price index', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: CardFrame(
            tier: RarityTier.vault,
            holo: true,
            child: CardIndex(cost: 1200, type: 'KEY'),
          ),
        ),
      ),
    );
    expect(find.text('1,200'), findsOneWidget);
    expect(find.text('KEY'), findsOneWidget);
    expect(find.byType(CardFrame), findsOneWidget);
  });

  testWidgets('CardIndex renders a free price', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: CardIndex(cost: 0, type: 'FILE')),
      ),
    );
    expect(find.text('0'), findsOneWidget);
  });

  test('rarityEdge differs per tier', () {
    expect(rarityEdge(RarityTier.vault), isA<LinearGradient>());
    expect(
      (rarityEdge(RarityTier.vault) as LinearGradient).colors,
      kGoldGradient.colors,
    );
    expect(
      (rarityEdge(RarityTier.standard) as LinearGradient).colors,
      isNot(kGoldGradient.colors),
    );
  });

  Widget host(Widget child, {bool reduced = false}) => MaterialApp(
    theme: AppTheme.dark,
    builder: (ctx, inner) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(disableAnimations: reduced),
      child: inner!,
    ),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('CardFlip lands once after 720ms', (tester) async {
    var landed = 0;
    await tester.pumpWidget(
      host(CardFlip(child: const Text('FACE'), onLanded: () => landed++)),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(landed, 0);
    await tester.pump(const Duration(milliseconds: 40));
    expect(landed, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(landed, 1);
  });

  testWidgets('CardFlip honours reduced motion and still calls back', (
    tester,
  ) async {
    var landed = 0;
    await tester.pumpWidget(
      host(
        CardFlip(child: const Text('FACE'), onLanded: () => landed++),
        reduced: true,
      ),
    );
    await tester.pump(); // post-frame callback
    expect(find.text('FACE'), findsOneWidget);
    expect(landed, 1);
  });

  testWidgets('FloatingCoin lands once at 900ms', (tester) async {
    var landed = 0;
    await tester.pumpWidget(
      host(
        FloatingCoin(
          from: const Offset(20, 300),
          to: const Offset(300, 40),
          label: '+10',
          onLanded: () => landed++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 880));
    expect(landed, 0);
    await tester.pump(const Duration(milliseconds: 40));
    expect(landed, 1);
  });
}
