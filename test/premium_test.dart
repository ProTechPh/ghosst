import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/premium.dart';
import 'package:ghosst/theme.dart';

void main() {
  group('groupDigits', () {
    test('adds thousand separators', () {
      expect(groupDigits(0), '0');
      expect(groupDigits(999), '999');
      expect(groupDigits(1000), '1,000');
      expect(groupDigits(1234567), '1,234,567');
      expect(groupDigits(-1234), '-1,234');
    });
  });

  group('monoStyle', () {
    test('uses JetBrainsMono with tabular figures', () {
      final s = monoStyle(fontSize: 12, fontWeight: FontWeight.w700);
      expect(s.fontFamily, 'JetBrainsMono');
      expect(s.fontSize, 12);
      expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
    });
  });

  testWidgets('StatCell renders label and value', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(
          body: StatCell(label: 'COINS', value: '1,234', icon: Icons.star)),
    ));
    expect(find.text('COINS'), findsOneWidget);
    expect(find.text('1,234'), findsOneWidget);
  });

  testWidgets('SectionHeader renders title and trailing', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: const Scaffold(
          body: SectionHeader(
              title: 'Store', trailing: Text('See all'))),
    ));
    expect(find.text('STORE'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('Eyebrow uppercases its text', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Eyebrow(text: 'hello world'))));
    expect(find.text('HELLO WORLD'), findsOneWidget);
  });

  testWidgets('Skeleton renders at its size', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Skeleton(width: 120, height: 16))));
    expect(find.byType(Skeleton), findsOneWidget);
    final box = tester.getSize(find.byType(Skeleton));
    expect(box.width, 120);
    expect(box.height, 16);
  });

  testWidgets('AnimatedCounter settles on the formatted value',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AnimatedCounter(value: 12345, prefix: '+'))));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('+12,345'), findsOneWidget);
  });

  testWidgets('IslandButton fires onPressed and shows busy state',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
          body: Column(children: [
        IslandButton(label: 'Claim', onPressed: () => taps++),
        const IslandButton(label: 'Loading', onPressed: null, busy: true),
      ])),
    ));
    await tester.tap(find.text('Claim'));
    expect(taps, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
