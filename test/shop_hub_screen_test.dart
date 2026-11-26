import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/shop_hub_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

Product _product(String id, String name) =>
    Product(id: id, name: name, cost: 500, active: true);

Claim _claim(String id, String name) => Claim(
  id: id,
  productId: id,
  productName: name,
  keyText: 'KEY-$id',
  cost: 250,
  createdAt: '2026-01-01T00:00:00.000Z',
);

Future<void> _pump(WidgetTester tester, {required ShopHubScreen screen}) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: screen));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 8 && target.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -220));
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(target, findsOneWidget);
}

void main() {
  testWidgets('dashboard shows balance, actions, keys, and featured products', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: ShopHubScreen(
        coins: 1250,
        onRefresh: () async {},
        onOpenEarn: () {},
        onOpenStore: () {},
        onOpenKeys: () {},
        onOpenTutorials: () {},
        onOpenWallet: () {},
        loadProducts: () async => [
          _product('p1', 'Featured Loader'),
          _product('p2', 'Featured App'),
        ],
        loadClaims: () async => [
          _claim('c1', 'My Premium Key'),
          _claim('c2', 'My Hour Key'),
        ],
      ),
    );

    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('1,250 coins'), findsOneWidget);
    expect(find.text('Earn coins'), findsOneWidget);
    expect(find.text('Browse store'), findsOneWidget);
    await _scrollTo(tester, find.text('YOUR KEYS'));
    expect(find.text('YOUR KEYS'), findsOneWidget);
    expect(find.text('My Premium Key'), findsOneWidget);
    expect(find.text('My Hour Key'), findsOneWidget);
    await _scrollTo(tester, find.text('Featured Loader'));
    expect(find.text('Featured Loader'), findsOneWidget);
    expect(find.text('Featured App'), findsOneWidget);
    await _scrollTo(tester, find.text('Tutorials'));
    expect(find.text('Tutorials'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
  });

  testWidgets('dashboard actions invoke their callbacks', (tester) async {
    final calls = <String>[];
    await _pump(
      tester,
      screen: ShopHubScreen(
        coins: 10,
        onRefresh: () async {},
        onOpenEarn: () => calls.add('earn'),
        onOpenStore: () => calls.add('store'),
        onOpenKeys: () => calls.add('keys'),
        onOpenTutorials: () => calls.add('tutorials'),
        onOpenWallet: () => calls.add('wallet'),
        loadProducts: () async => const [],
        loadClaims: () async => const [],
      ),
    );

    await tester.tap(find.text('Earn coins'));
    await tester.tap(find.text('Browse store'));
    await tester.tap(find.byKey(const ValueKey('shop-open-keys')));
    await _scrollTo(tester, find.text('Tutorials'));
    await tester.tap(find.text('Tutorials'));
    await tester.tap(find.text('Wallet'));
    await tester.pump();

    expect(calls, ['earn', 'store', 'keys', 'tutorials', 'wallet']);
  });

  testWidgets('product failure does not block balance or primary actions', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: ShopHubScreen(
        coins: 77,
        onRefresh: () async {},
        onOpenEarn: () {},
        onOpenStore: () {},
        onOpenKeys: () {},
        onOpenTutorials: () {},
        onOpenWallet: () {},
        loadProducts: () async => throw Exception('offline'),
        loadClaims: () async => [_claim('c1', 'My Premium Key')],
      ),
    );

    expect(find.text('77'), findsOneWidget);
    expect(find.text('Earn coins'), findsOneWidget);
    expect(find.text('Browse store'), findsOneWidget);
    expect(find.text('My Premium Key'), findsOneWidget);
    expect(find.text('Could not load featured products'), findsOneWidget);
  });
}
