import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/theme.dart';

void main() {
  test('dark theme is dark with the brand tokens', () {
    final t = AppTheme.dark;
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, AppColors.bg);
    expect(t.colorScheme.primary, AppColors.primary);
  });

  test('token scales are ordered and positive', () {
    expect(AppSpace.xs, lessThan(AppSpace.sm));
    expect(AppSpace.sm, lessThan(AppSpace.md));
    expect(AppSpace.md, lessThan(AppSpace.lg));
    expect(AppRadius.chip, lessThan(AppRadius.card));
    expect(kTouchMin, 48);
    expect(AppText.figure.fontFeatures,
        contains(const FontFeature.tabularFigures()));
  });

  testWidgets('CoinPill shows the balance and reports taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home:
          Scaffold(body: CoinPill(coins: 250, onTap: () => taps++)),
    ));
    expect(find.text('250'), findsOneWidget);
    await tester.tap(find.byType(CoinPill));
    expect(taps, 1);
  });

  testWidgets('NeonPill renders its label', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: NeonPill(
              label: 'KEY', icon: Icons.key, color: AppColors.cyan)),
    ));
    expect(find.text('KEY'), findsOneWidget);
  });

  testWidgets('GradientText renders the given text', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: GradientText('GHOSST'))));
    expect(find.text('GHOSST'), findsOneWidget);
  });

  testWidgets('GlowCard renders its child and fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: GlowCard(onTap: () => taps++, child: const Text('X'))),
    ));
    expect(find.text('X'), findsOneWidget);
    await tester.tap(find.text('X'));
    expect(taps, 1);
  });

  testWidgets('EmptyState renders title, message and action',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: EmptyState(
              icon: Icons.inbox,
              title: 'Nothing here',
              message: 'Try again later',
              action: Text('Retry'))),
    ));
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Try again later'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('SectionLabel uppercases', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SectionLabel('recent'))));
    expect(find.text('RECENT'), findsOneWidget);
  });

  testWidgets('NeonButton taps when enabled, not when disabled',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
          body: Column(children: [
        NeonButton(onPressed: () => taps++, child: const Text('Go')),
        const NeonButton(onPressed: null, child: Text('Off')),
      ])),
    ));
    await tester.tap(find.text('Go'));
    expect(taps, 1);
    await tester.tap(find.text('Off'), warnIfMissed: false);
    expect(taps, 1);
  });

  testWidgets('LogoBadge renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LogoBadge(size: 40))));
    expect(find.byType(LogoBadge), findsOneWidget);
  });
}
