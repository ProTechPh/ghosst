import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/arcade.dart';
import 'package:ghosst/screens/claim_reveal.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

Product _product() =>
    Product(id: 'p1', name: 'Ghosst Pro', cost: 300, active: true);

Widget _host({required bool reduced}) => MaterialApp(
  theme: AppTheme.dark,
  builder: (ctx, inner) => MediaQuery(
    data: MediaQuery.of(ctx).copyWith(disableAnimations: reduced),
    child: inner!,
  ),
  home: Scaffold(
    body: Builder(
      builder: (ctx) => TextButton(
        onPressed: () => showClaimFlow(
          context: ctx,
          product: _product(),
          balanceBefore: 500,
          cost: 300,
          claim: () async => 'KEY-TEST-1234',
        ),
        child: const Text('go'),
      ),
    ),
  ),
);

Finder _keyText() => find.byWidgetPredicate(
  (w) => w is SelectableText && w.data == 'KEY-TEST-1234',
);

void main() {
  testWidgets('key reveal shows the key and fires one haptic', (tester) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_host(reduced: false));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2200)); // floor reached
    expect(find.text('GHOSST'), findsOneWidget); // card back is showing
    expect(_keyText(), findsNothing); // still on the card back
    expect(haptics, isEmpty);
    await tester.pump(const Duration(milliseconds: 900)); // flip lands
    expect(find.byType(CardFlip), findsOneWidget);
    expect(_keyText(), findsOneWidget);
    expect(haptics.length, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(haptics.length, 1); // no double fire
  });

  testWidgets('reduced motion still shows the key and fires one haptic', (
    tester,
  ) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_host(reduced: true));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2200)); // floor only
    await tester.pump(); // post-frame landing callback
    expect(_keyText(), findsOneWidget);
    expect(haptics.length, 1);
  });

  testWidgets('reveal rarity uses the entry price, not the duration price', (
    tester,
  ) async {
    final tiered = Product(
      id: 'p2',
      name: 'Vault Key',
      cost: 1200,
      active: true,
      durations: const [
        ProductDuration(label: '1 day', cost: 1200),
        ProductDuration(label: '30 days', cost: 4000),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showClaimFlow(
                context: ctx,
                product: tiered,
                balanceBefore: 5000,
                cost: 4000,
                claim: () async => 'KEY-TEST-1234',
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 3000));
    expect(
      tester.widget<CardFlip>(find.byType(CardFlip)).tier,
      RarityTier.plus,
    );
  });
}
