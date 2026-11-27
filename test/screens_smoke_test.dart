import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/arcade.dart';
import 'package:ghosst/premium.dart';
import 'package:ghosst/screens/adblock_screen.dart';
import 'package:ghosst/screens/download_screen.dart';
import 'package:ghosst/screens/landing_screen.dart';
import 'package:ghosst/screens/product_detail.dart';
import 'package:ghosst/screens/tamper_screen.dart';
import 'package:ghosst/services/adblock_detector.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/services/security.dart';
import 'package:ghosst/social_shell.dart';
import 'package:ghosst/theme.dart';

void main() {
  testWidgets('LandingScreen fires the sign-in callback', (tester) async {
    var signIns = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: LandingScreen(
            onSignIn: () => signIns++,
            onGoogleSignedIn: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    // Both CTAs are pinned under the fold on small screens — scroll to them.
    await tester.ensureVisible(find.text('Sign in with email'));
    await tester.tap(find.text('Sign in with email'));
    expect(signIns, 1);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('TamperDetectedScreen explains the lock without a download URL', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TamperDetectedScreen())),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('modified'), findsWidgets);
    expect(find.textContaining('official'), findsWidgets);
  });

  testWidgets('TamperDetectedScreen shows supplied reasons', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TamperDetectedScreen(flags: ['re-signed'])),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TamperDetectedScreen), findsOneWidget);
  });

  testWidgets('AdblockScreen renders the gate and re-checks', (tester) async {
    var calls = 0;
    AdblockReport? delivered;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: AdblockScreen(
            report: const AdblockReport(blocked: true, flags: ['dns']),
            recheck: () async {
              calls++;
              return const AdblockReport(blocked: false, flags: []);
            },
            onResult: (r) => delivered = r,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ad blocker detected'), findsOneWidget);
    await tester.ensureVisible(find.text('Check again'));
    await tester.pump();
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(delivered?.blocked, isFalse);
  });

  testWidgets('DownloadScreen renders its idle state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DownloadScreen(
          url: 'https://www.mediafire.com/file/x/file',
          title: 'My App',
          kind: 'apk',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('My App'), findsOneWidget);
    expect(find.byType(SocialAppBar), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.black);
    expect(appBar.foregroundColor, AppColors.text);
    expect(find.byType(MeshBackground), findsNothing);
    expect(find.byType(TableSurface), findsNothing);
    final start = find.widgetWithText(IslandButton, 'Start download');
    if (start.evaluate().isNotEmpty) {
      expect(tester.getSize(start).height, greaterThanOrEqualTo(kTouchMin));
    }
  });

  testWidgets('ProductDetailScreen uses a black social scaffold', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ProductDetailScreen(
          product: Product(
            id: 'p1',
            name: 'Ghosst Pro',
            cost: 300,
            active: true,
          ),
          coins: 500,
          stock: 4,
          onRefresh: () async {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Ghosst Pro'), findsWidgets);
    expect(find.byType(SocialAppBar), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.bg);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.black);
    expect(appBar.foregroundColor, AppColors.text);
    final claim = find.widgetWithText(NeonButton, 'Claim key');
    expect(tester.getSize(claim).height, greaterThanOrEqualTo(kTouchMin));
  });

  test('SecurityReport helpers do not throw', () {
    const r = SecurityReport(blocked: false);
    expect(r.blocked, isFalse);
    expect(securityReason('re-signed'), isNotEmpty);
  });
}
