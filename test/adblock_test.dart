import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/appwrite_client.dart';
import 'package:ghosst/premium.dart';
import 'package:ghosst/screens/adblock_screen.dart';
import 'package:ghosst/services/adblock_detector.dart';
import 'package:ghosst/theme.dart';

/// The control host runCheck probes (derived from the endpoint just like
/// production code does).
final String controlHost = Uri.parse(appwriteEndpoint).host;

final InternetAddress _realIp = InternetAddress('93.184.216.34');
final InternetAddress _sinkhole = InternetAddress('0.0.0.0');

HostResolver _resolver({
  bool controlDown = false,
  Set<String> sinkholed = const <String>{},
}) {
  return (String host) async {
    if (host == controlHost) return controlDown ? null : [_realIp];
    if (sinkholed.contains(host)) return [_sinkhole];
    return [_realIp];
  };
}

UrlProber _prober({bool controlUnreachable = false, Set<String> refused = const <String>{}}) {
  return (Uri url) async {
    if (url.host == controlHost) return !controlUnreachable;
    return !refused.contains(url.host);
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdblockDetector.runCheck', () {
    test('blocks when the control answers and 2+ ad hosts are sinkholed', () async {
      final report = await AdblockDetector.runCheck(
        resolve: _resolver(
          sinkholed: const {
            'pagead2.googlesyndication.com',
            'googleads.g.doubleclick.net',
          },
        ),
        probe: _prober(),
      );

      expect(report.blocked, isTrue);
      expect(report.flags, contains('dns:pagead2.googlesyndication.com'));
      expect(report.flags, contains('dns:googleads.g.doubleclick.net'));
      // The third host answered — kept out of the flags.
      expect(report.flags.where((f) => f.startsWith('dns:adservice')), isEmpty);
    });

    test('names the Private DNS server once blocked', () async {
      final report = await AdblockDetector.runCheck(
        resolve: _resolver(
          sinkholed: const {
            'pagead2.googlesyndication.com',
            'adservice.google.com',
          },
        ),
        probe: _prober(),
        privateDns: () async => 'dns.adguard.com',
      );

      expect(report.blocked, isTrue);
      expect(report.flags, contains('private-dns:dns.adguard.com'));
      expect(
        report.flags.map(adblockReason),
        contains('Private DNS is set to dns.adguard.com'),
      );
    });

    test('never blocks when the control host cannot resolve', () async {
      final report = await AdblockDetector.runCheck(
        resolve: _resolver(
          controlDown: true,
          sinkholed: const {
            'pagead2.googlesyndication.com',
            'googleads.g.doubleclick.net',
            'adservice.google.com',
          },
        ),
        probe: _prober(),
      );

      expect(report.blocked, isFalse);
      expect(report.flags, ['offline']);
    });

    test('never blocks when the control host cannot be reached', () async {
      final report = await AdblockDetector.runCheck(
        resolve: _resolver(
          sinkholed: const {
            'pagead2.googlesyndication.com',
            'adservice.google.com',
          },
        ),
        probe: _prober(controlUnreachable: true),
      );

      expect(report.blocked, isFalse);
      expect(report.flags, ['offline']);
    });

    test('one flaky host out of three does not lock the app', () async {
      final report = await AdblockDetector.runCheck(
        resolve: _resolver(
          sinkholed: const {'pagead2.googlesyndication.com'},
        ),
        probe: _prober(),
      );

      expect(report.blocked, isFalse);
      // The evidence is still recorded for the reasons card.
      expect(report.flags, ['dns:pagead2.googlesyndication.com']);
    });

    test('flags hosts that resolve but refuse the connection', () async {
      final report = await AdblockDetector.runCheck(
        resolve: _resolver(),
        probe: _prober(
          refused: const {
            'googleads.g.doubleclick.net',
            'adservice.google.com',
          },
        ),
      );

      expect(report.blocked, isTrue);
      expect(report.flags, contains('http:googleads.g.doubleclick.net'));
      expect(report.flags, contains('http:adservice.google.com'));
      expect(report.flags.where((f) => f.startsWith('dns:')), isEmpty);
    });

    test('a throwing resolver reads as offline, not as blocked', () async {
      final report = await AdblockDetector.runCheck(
        resolve: (_) async => throw StateError('resolver broke'),
        probe: _prober(),
      );

      expect(report.blocked, isFalse);
      expect(report.flags, ['offline']);
    });
  });

  group('adblockReason', () {
    test('translates a DNS block', () {
      expect(
        adblockReason('dns:pagead2.googlesyndication.com'),
        'pagead2.googlesyndication.com is blocked by a DNS filter',
      );
    });

    test('translates an HTTP-level block', () {
      expect(
        adblockReason('http:adservice.google.com'),
        'adservice.google.com is blocked by a network filter '
            '(VPN or firewall)',
      );
    });

    test('translates the Private DNS hostname', () {
      expect(
        adblockReason('private-dns:dns.adguard.com'),
        'Private DNS is set to dns.adguard.com',
      );
    });

    test('explains the offline verdict', () {
      expect(
        adblockReason('offline'),
        'No internet connection to verify ads',
      );
    });

    test('degrades to the raw flag when unknown', () {
      expect(adblockReason('future-flag'), 'future flag');
    });
  });

  group('AdblockScreen', () {
    const blockingReport = AdblockReport(
      blocked: true,
      flags: [
        'dns:pagead2.googlesyndication.com',
        'private-dns:dns.adguard.com',
      ],
    );

    testWidgets('shows the verdict, the reasons and the fix steps', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: AdblockScreen(
            report: blockingReport,
            recheck: () async => blockingReport,
            onResult: (_) {},
          ),
        ),
      );

      expect(find.text('Ad blocker detected'), findsOneWidget);
      expect(
        find.text(
          'pagead2.googlesyndication.com is blocked by a DNS filter',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Private DNS is set to dns.adguard.com'),
        findsOneWidget,
      );
      expect(find.text('GET BACK IN'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.textContaining('ADS KEEP GHOSST FREE'), findsOneWidget);
    });

    testWidgets('hands the re-check verdict back to the gate', (tester) async {
      AdblockReport? got;
      await tester.pumpWidget(
        _GateHarness(
          recheck: () async => const AdblockReport(
            blocked: true,
            flags: ['http:adservice.google.com'],
          ),
          onResult: (r) => got = r,
        ),
      );

      await tester.ensureVisible(
        find.widgetWithText(IslandButton, 'Check again'),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(IslandButton, 'Check again'));
      await tester.pumpAndSettle();

      expect(got, isNotNull);
      expect(got!.blocked, isTrue);
      expect(got!.flags, contains('http:adservice.google.com'));
      // Still blocked → the reasons card follows the fresh verdict.
      expect(
        find.text(
          'adservice.google.com is blocked by a network filter '
              '(VPN or firewall)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('lifts the gate when the re-check comes back clean', (
      tester,
    ) async {
      AdblockReport? got;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: AdblockScreen(
            report: blockingReport,
            recheck: () async => AdblockReport.clean,
            onResult: (r) => got = r,
          ),
        ),
      );

      await tester.ensureVisible(
        find.widgetWithText(IslandButton, 'Check again'),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(IslandButton, 'Check again'));
      await tester.pumpAndSettle();

      expect(got, isNotNull);
      expect(got!.blocked, isFalse);
      expect(got!.flags, isEmpty);
    });

    testWidgets('a broken probe keeps the gate up', (tester) async {
      AdblockReport? got;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: AdblockScreen(
            report: blockingReport,
            recheck: () async => throw StateError('probe broke'),
            onResult: (r) => got = r,
          ),
        ),
      );

      await tester.ensureVisible(
        find.widgetWithText(IslandButton, 'Check again'),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(IslandButton, 'Check again'));
      await tester.pumpAndSettle();

      // Old verdict handed back verbatim — no unlock on an error.
      expect(got, isNotNull);
      expect(got!.blocked, isTrue);
      expect(
        find.text('pagead2.googlesyndication.com is blocked by a DNS filter'),
        findsOneWidget,
      );
      expect(find.text('Check again'), findsOneWidget);
    });
  });
}

/// Mirrors how `main.dart` owns the verdict: `onResult` writes the fresh
/// report back into the `report` prop, so the reasons card follows it (or
/// the parent would swap the gate out entirely when it comes back clean).
class _GateHarness extends StatefulWidget {
  const _GateHarness({required this.recheck, this.onResult});

  final Future<AdblockReport> Function() recheck;
  final ValueChanged<AdblockReport>? onResult;

  @override
  State<_GateHarness> createState() => _GateHarnessState();
}

class _GateHarnessState extends State<_GateHarness> {
  static const _initial = AdblockReport(
    blocked: true,
    flags: [
      'dns:pagead2.googlesyndication.com',
      'private-dns:dns.adguard.com',
    ],
  );

  AdblockReport _report = _initial;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: AdblockScreen(
        report: _report,
        recheck: widget.recheck,
        onResult: (r) {
          widget.onResult?.call(r);
          setState(() => _report = r);
        },
      ),
    );
  }
}
