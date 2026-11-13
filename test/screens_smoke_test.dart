import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/adblock_screen.dart';
import 'package:ghosst/screens/download_screen.dart';
import 'package:ghosst/screens/landing_screen.dart';
import 'package:ghosst/screens/tamper_screen.dart';
import 'package:ghosst/services/adblock_detector.dart';
import 'package:ghosst/services/security.dart';
import 'package:ghosst/theme.dart';

void main() {
  testWidgets('LandingScreen fires the sign-in callback', (tester) async {
    var signIns = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
          body: LandingScreen(
              onSignIn: () => signIns++, onGoogleSignedIn: () {})),
    ));
    await tester.pump(const Duration(milliseconds: 1500));
    // Both CTAs are pinned under the fold on small screens — scroll to them.
    await tester.ensureVisible(find.text('Sign in with email'));
    await tester.tap(find.text('Sign in with email'));
    expect(signIns, 1);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('TamperDetectedScreen explains the lock without a download URL',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: TamperDetectedScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('modified'), findsWidgets);
    expect(find.textContaining('official'), findsWidgets);
  });

  testWidgets('TamperDetectedScreen shows supplied reasons',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: TamperDetectedScreen(flags: ['re-signed'])),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TamperDetectedScreen), findsOneWidget);
  });

  testWidgets('AdblockScreen renders the gate and re-checks', (tester) async {
    var calls = 0;
    AdblockReport? delivered;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
          body: AdblockScreen(
        report: const AdblockReport(blocked: true, flags: ['dns']),
        recheck: () async {
          calls++;
          return const AdblockReport(blocked: false, flags: []);
        },
        onResult: (r) => delivered = r,
      )),
    ));
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
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: DownloadScreen(
              url: 'https://www.mediafire.com/file/x/file',
              title: 'My App',
              kind: 'apk')),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('My App'), findsOneWidget);
  });

  test('SecurityReport helpers do not throw', () {
    const r = SecurityReport(blocked: false);
    expect(r.blocked, isFalse);
    expect(securityReason('re-signed'), isNotEmpty);
  });
}
