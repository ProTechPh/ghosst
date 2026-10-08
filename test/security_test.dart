import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/premium.dart';
import 'package:ghosst/screens/tamper_screen.dart';
import 'package:ghosst/services/apk_download.dart';
import 'package:ghosst/services/backend.dart';
import 'package:ghosst/services/security.dart';
import 'package:ghosst/theme.dart';

/// Drives the native integrity channel the way MainActivity.kt answers it.
void mockNative(Object? value) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(Security.channel, (_) async => value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(Security.channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(OfficialApk.channel, null);
  });

  group('Security.verifyIntegrity', () {
    test('blocks a tampered verdict and keeps every flag', () async {
      mockNative(<Object?, Object?>{
        'blocked': true,
        'flags': <Object?>['signature-mismatch', 'debuggable-build'],
      });

      final report = await Security.verifyIntegrity();

      expect(report.blocked, isTrue);
      expect(report.flags, ['signature-mismatch', 'debuggable-build']);
      expect(
        report.flags.map(securityReason),
        [
          "App signature doesn't match the official release",
          'Debug build — not an official release',
        ],
      );
    });

    test('passes a clean verdict through', () async {
      mockNative(<Object?, Object?>{'blocked': false, 'flags': <Object?>[]});

      final report = await Security.verifyIntegrity();

      expect(report.blocked, isFalse);
      expect(report.flags, isEmpty);
    });

    test('blocks on flags even if native forgets the blocked key', () async {
      mockNative(<Object?, Object?>{
        'flags': <Object?>['package-changed'],
      });

      final report = await Security.verifyIntegrity();

      expect(report.blocked, isTrue);
    });

    test('fails open when the platform throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Security.channel, (_) async {
            throw PlatformException(code: 'channel-broken');
          });

      final report = await Security.verifyIntegrity();

      expect(report.blocked, isFalse);
      expect(report.flags, isEmpty);
    });

    test('fails open when the native side is missing entirely', () async {
      // No handler registered → MissingPluginException (iOS / stripped build).
      final report = await Security.verifyIntegrity();

      expect(report.blocked, isFalse);
    });

    test('fails open on a malformed answer', () async {
      mockNative('tampered');

      final report = await Security.verifyIntegrity();

      expect(report.blocked, isFalse);
    });
  });

  group('securityReason', () {
    test('names a modding tool without leaking the package id', () {
      expect(
        securityReason('mod-installer:com.chelpus.lackypatch'),
        'Installed through a modding tool',
      );
    });

    test('degrades to the raw flag when unknown', () {
      expect(securityReason('future-flag'), 'future flag');
    });
  });

  group('TamperDetectedScreen', () {
    testWidgets('shows the verdict, the reason and the official download', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: TamperDetectedScreen(
            info: UpdateInfo(
              versionCode: 17,
              versionName: '2.0.1',
              url: 'https://www.mediafire.com/file/official.apk',
            ),
            flags: const ['signature-mismatch'],
          ),
        ),
      );

      expect(find.text('Official app required'), findsOneWidget);
      expect(
        find.text("App signature doesn't match the official release"),
        findsOneWidget,
      );
      expect(find.text('Download official app'), findsOneWidget);
      expect(find.text('Remove this copy'), findsOneWidget);
      // The link is never printed — the app downloads the file itself.
      expect(find.textContaining('mediafire'), findsNothing);
      expect(find.textContaining('github.com'), findsNothing);
    });

    testWidgets('downloads in-app instead of printing the link', (
      tester,
    ) async {
      // Native download is unavailable in this harness — the screen must
      // report that instead of falling back to a browser.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(OfficialApk.channel, (call) async {
            throw PlatformException(
              code: 'download-failed',
              message: 'Could not start the download',
            );
          });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: TamperDetectedScreen(
            info: UpdateInfo(
              versionCode: 17,
              versionName: '2.0.1',
              url: 'https://example.com/ghosst-official.apk',
            ),
            flags: const ['signature-mismatch'],
          ),
        ),
      );

      await tester.ensureVisible(
        find.widgetWithText(IslandButton, 'Download official app'),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(IslandButton, 'Download official app'));
      await tester.pumpAndSettle();

      // The link never leaks into the UI — the download stays in-app.
      expect(find.textContaining('https://example.com'), findsNothing);
      expect(find.textContaining('browser instead'), findsOneWidget);
    });

    testWidgets('Remove this copy asks Android to uninstall the app', (
      tester,
    ) async {
      String? called;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(Security.channel, (call) async {
            called = call.method;
            return true;
          });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const TamperDetectedScreen(flags: ['signature-mismatch']),
        ),
      );

      await tester.ensureVisible(
        find.widgetWithText(IslandButton, 'Remove this copy'),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(IslandButton, 'Remove this copy'));
      await tester.pumpAndSettle();

      expect(called, 'uninstallSelf');
    });

    testWidgets('disables the download when no official link exists', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const TamperDetectedScreen(flags: ['signature-mismatch']),
        ),
      );

      final button = tester.widget<IslandButton>(
        find.widgetWithText(IslandButton, 'Download official app'),
      );
      expect(button.onPressed, isNull);
      // No link to print either — the button is the only dead affordance.
      expect(find.textContaining('mediafire'), findsNothing);
    });

    testWidgets('falls back to the hardcoded official link', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: TamperDetectedScreen(
            info: UpdateInfo(
              versionCode: 0,
              versionName: '',
              url: 'https://example.com/ghosst-official.apk',
            ),
          ),
        ),
      );

      final button = tester.widget<IslandButton>(
        find.widgetWithText(IslandButton, 'Download official app'),
      );
      expect(button.onPressed, isNotNull);
    });
  });
}
