import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/theme.dart';

double _contrast(Color a, Color b) {
  double linear(int channel) {
    final value = channel / 255.0;
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  double luminance(Color color) {
    final argb = color.toARGB32();
    return 0.2126 * linear((argb >> 16) & 0xff) +
        0.7152 * linear((argb >> 8) & 0xff) +
        0.0722 * linear(argb & 0xff);
  }

  final first = luminance(a);
  final second = luminance(b);
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('dark theme is dark with the hybrid brand tokens', () {
    final t = AppTheme.dark;
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, AppColors.bg);
    expect(t.colorScheme.primary, AppColors.primary);
    expect(AppColors.bg, const Color(0xFF0B0F12));
    expect(AppColors.surface, const Color(0xFF171D23));
    expect(AppColors.surfaceHigh, const Color(0xFF26323B));
    expect(AppColors.primary, const Color(0xFF22D3EE));
    expect(AppColors.gold, const Color(0xFFFBBF24));
    expect(AppColors.red, const Color(0xFFF43F5E));
    expect(t.navigationBarTheme.backgroundColor, Colors.black);
    expect(t.navigationBarTheme.height, 64);
    expect(_contrast(AppColors.text, AppColors.bg), greaterThanOrEqualTo(4.5));
    expect(
      _contrast(AppColors.textDim, AppColors.surface),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('token scales are ordered and positive', () {
    expect(AppSpace.xs, lessThan(AppSpace.sm));
    expect(AppSpace.sm, lessThan(AppSpace.md));
    expect(AppSpace.md, lessThan(AppSpace.lg));
    expect(AppRadius.chip, lessThan(AppRadius.card));
    expect(kTouchMin, 48);
    expect(
      AppText.figure.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('CoinPill shows the balance and reports taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: CoinPill(coins: 250, onTap: () => taps++)),
      ),
    );
    expect(find.text('250'), findsOneWidget);
    await tester.tap(find.byType(CoinPill));
    expect(taps, 1);
  });

  testWidgets('NeonPill renders its label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NeonPill(label: 'KEY', icon: Icons.key, color: AppColors.cyan),
        ),
      ),
    );
    expect(find.text('KEY'), findsOneWidget);
  });

  testWidgets('GradientText renders the given text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: GradientText('GHOSST'))),
    );
    expect(find.text('GHOSST'), findsOneWidget);
  });

  testWidgets('GlowCard renders its child and fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlowCard(onTap: () => taps++, child: const Text('X')),
        ),
      ),
    );
    expect(find.text('X'), findsOneWidget);
    await tester.tap(find.text('X'));
    expect(taps, 1);
  });

  testWidgets('EmptyState renders title, message and action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.inbox,
            title: 'Nothing here',
            message: 'Try again later',
            action: Text('Retry'),
          ),
        ),
      ),
    );
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Try again later'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('SectionLabel uppercases', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SectionLabel('recent'))),
    );
    expect(find.text('RECENT'), findsOneWidget);
  });

  testWidgets('NeonButton taps when enabled, not when disabled', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Column(
            children: [
              NeonButton(onPressed: () => taps++, child: const Text('Go')),
              const NeonButton(onPressed: null, child: Text('Off')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Go'));
    expect(taps, 1);
    await tester.tap(find.text('Off'), warnIfMissed: false);
    expect(taps, 1);
  });

  testWidgets('LogoBadge renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LogoBadge(size: 40))),
    );
    expect(find.byType(LogoBadge), findsOneWidget);
  });
}
