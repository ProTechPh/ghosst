import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/admin_screen.dart';
import 'package:ghosst/screens/feedback_screen.dart';
import 'package:ghosst/screens/profile_screen.dart';
import 'package:ghosst/screens/wallet_screen.dart';
import 'package:ghosst/social_shell.dart';
import 'package:ghosst/theme.dart';

void _tallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('account screens use solid social surfaces and shared app bars', () {
    for (final file in [
      'wallet_screen.dart',
      'feedback_screen.dart',
      'admin_screen.dart',
      'profile_screen.dart',
    ]) {
      final source = File('lib/screens/$file').readAsStringSync();
      expect(source.contains('MeshBackground'), isFalse, reason: file);
      expect(source.contains('TableSurface'), isFalse, reason: file);
      expect(source.contains('SocialAppBar'), isTrue, reason: file);
    }
  });

  testWidgets('Wallet route uses the social shell', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: WalletScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.byType(SocialAppBar), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.bg);
  });

  testWidgets('Profile settings route uses the social shell while loading', (
    tester,
  ) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ProfileScreen(
          onSignOut: () {},
          onAccountDeleted: () {},
          onOpenKeys: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Profile'), findsOneWidget);
    expect(find.byType(SocialAppBar), findsOneWidget);
  });

  testWidgets('Admin route owns its social scaffold', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(const MaterialApp(home: AdminScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Admin'), findsOneWidget);
    expect(find.byType(SocialAppBar), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.bg);
  });

  testWidgets('Feedback route uses the shared black app bar', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: FeedbackScreen(loadMine: () async => const []),
      ),
    );
    await tester.pump();
    expect(find.byType(SocialAppBar), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.black);
  });
}
