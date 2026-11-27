import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/earn_screen.dart';
import 'package:ghosst/screens/my_keys_screen.dart';
import 'package:ghosst/screens/store_screen.dart';
import 'package:ghosst/screens/tutorials_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/social_shell.dart';
import 'package:ghosst/theme.dart';

void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('commerce screens use solid social surfaces and shared app bars', () {
    for (final file in [
      'store_screen.dart',
      'earn_screen.dart',
      'my_keys_screen.dart',
      'tutorials_screen.dart',
    ]) {
      final source = File('lib/screens/$file').readAsStringSync();
      expect(source.contains('MeshBackground'), isFalse, reason: file);
      expect(source.contains('TableSurface'), isFalse, reason: file);
      expect(source.contains('SocialAppBar'), isTrue, reason: file);
    }
    for (final file in ['store_screen.dart', 'my_keys_screen.dart']) {
      final source = File('lib/screens/$file').readAsStringSync();
      expect(source.contains('EmptyState('), isTrue, reason: file);
      expect(source.contains("'Retry'"), isTrue, reason: file);
    }
  });

  testWidgets('Store route exposes a social app bar and error retry', (
    tester,
  ) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: StoreScreen(coins: 0, onRefresh: () async {}),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Store'), findsOneWidget);
    expect(find.byType(SocialAppBar), findsOneWidget);
  });

  testWidgets('Earn route exposes a social app bar', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: EarnScreen(coins: 0, onRefresh: () async {}),
      ),
    );
    await tester.pump();
    expect(find.text('Earn coins'), findsWidgets);
    expect(find.byType(SocialAppBar), findsOneWidget);
  });

  testWidgets('Purchases route exposes a social app bar', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MyKeysScreen(onGoToStore: () {}),
      ),
    );
    await tester.pump();
    expect(find.text('Purchases'), findsOneWidget);
    expect(find.byType(SocialAppBar), findsOneWidget);
  });

  testWidgets('Tutorials route uses the shared black app bar', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: TutorialsScreen(
          load: () async => [
            Tutorial(
              id: 1,
              title: 'Guide',
              slug: 'guide',
              category: 'General',
              videoUrl: '',
              content: 'Text guide',
              views: 0,
              createdAt: '',
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SocialAppBar), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.black);
  });
}
