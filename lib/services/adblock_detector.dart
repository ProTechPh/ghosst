import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../appwrite_client.dart';
import 'security.dart';

/// Verdict of the ad-blocker check.
@immutable
class AdblockReport {
  const AdblockReport({required this.blocked, this.flags = const <String>[]});

  /// True when ads are being blocked and the app must stay locked.
  final bool blocked;

  /// Raw machine flags, e.g. `dns:pagead2.googlesyndication.com`,
  /// `http:adservice.google.com`, `private-dns:dns.adguard.com`.
  final List<String> flags;

  static const AdblockReport clean = AdblockReport(blocked: false);

  /// Could not verify (offline, timeout, broken probe) — never a block.
  static const AdblockReport inconclusive = AdblockReport(
    blocked: false,
    flags: ['offline'],
  );
}

/// Resolves a host. `null` means resolution failed outright.
typedef HostResolver = Future<List<InternetAddress>?> Function(String host);

/// Probes a URL. `true` means the URL answered with ANY HTTP status —
/// only a connection-level failure counts as blocked.
typedef UrlProber = Future<bool> Function(Uri url);

/// Cold-start ad-blocker detection — Ghosst is free because of ads, so the
/// app refuses to run on a device that filters them out.
///
/// Signal design: probe **real AdMob endpoints** against our own backend as
/// the control. The backend must answer first (else the check is
/// inconclusive — no network is not evidence of blocking); only then are
/// ad-host failures treated as blocking. Two independent layers are checked
/// per host: DNS (sinkhole answers like `0.0.0.0`, or resolution failure)
/// and HTTP (connection refused / reset by a VPN or firewall filter).
///
/// Policy: **fail open**, same as [Security]. Offline, timeout, a broken
/// channel or a flaky single host must never brick a legitimate launch —
/// [AdblockReport.blocked] only ever turns true on positive evidence
/// (2 of 3 ad hosts blocked while the control host is reachable).
class AdblockDetector {
  /// Real AdMob endpoints — all three sit on the standard blocklists
  /// (AdGuard, EasyList, NextDNS), so a filter that matters hits them.
  static const List<String> adHosts = [
    'pagead2.googlesyndication.com',
    'googleads.g.doubleclick.net',
    'adservice.google.com',
  ];

  /// Hosts must agree: one flaky DNS answer or one geo quirk must not lock
  /// the app. Two of three blocked while the control host answers = real.
  static const int _threshold = 2;

  /// Runs the full check. Injectable seams let tests drive [runCheck]
  /// without touching the network; production wires the real probes.
  ///
  /// The whole run is bounded by [timeout] and any failure (including the
  /// timeout itself) degrades to [AdblockReport.inconclusive] — never a
  /// block.
  static Future<AdblockReport> check({
    Duration timeout = const Duration(milliseconds: 4500),
    HostResolver? resolve,
    UrlProber? probe,
    Future<String?> Function()? privateDns,
  }) async {
    try {
      return await runCheck(
        resolve: resolve ?? _resolve,
        probe: probe ?? _probe,
        privateDns: privateDns ?? _privateDns,
      ).timeout(timeout);
    } catch (_) {
      // Timeout, socket blowup, hostile network — fail open.
      return AdblockReport.inconclusive;
    }
  }

  /// The pure verdict logic, extracted so tests can inject fake probes.
  ///
  /// 1. Control chain: the Appwrite backend must resolve *and* answer HTTP.
  ///    Either failing means the device has no usable network → offline.
  /// 2. Ad chains run in parallel; each failing host records a flag
  ///    (`dns:` when resolution/sinkhole failed, `http:` when the connection
  ///    was refused or reset).
  /// 3. Block only when at least [_threshold] ad hosts are flagged. The
  ///    Private DNS hostname, when there is one, is appended afterwards as
  ///    informational context — it never triggers the gate on its own
  ///    (a custom DNS server can be privacy-only).
  @visibleForTesting
  static Future<AdblockReport> runCheck({
    required HostResolver resolve,
    required UrlProber probe,
    Future<String?> Function()? privateDns,
  }) async {
    final controlHost = Uri.parse(appwriteEndpoint).host;
    final results = await Future.wait<_Chain>([
      _probeHost(
        resolve,
        probe,
        controlHost,
        Uri.parse('$appwriteEndpoint/health'),
      ),
      for (final host in adHosts)
        _probeHost(resolve, probe, host, Uri.parse('https://$host/')),
    ]);

    // No usable network to compare against — nothing to prove.
    final control = results.first;
    if (!control.dns || !control.http) return AdblockReport.inconclusive;

    final flags = <String>[];
    for (var i = 0; i < adHosts.length; i++) {
      final chain = results[i + 1];
      if (!chain.dns) {
        flags.add('dns:${adHosts[i]}');
      } else if (!chain.http) {
        flags.add('http:${adHosts[i]}');
      }
    }

    if (flags.length < _threshold) {
      return AdblockReport(blocked: false, flags: flags);
    }

    // Informational only: names the custom server on the gate screen.
    if (privateDns != null) {
      try {
        final spec = await privateDns();
        if (spec != null && spec.isNotEmpty) flags.add('private-dns:$spec');
      } catch (_) {
        // Missing channel / odd answer — the verdict already stands.
      }
    }
    return AdblockReport(blocked: true, flags: flags);
  }

  /// One host, two layers: resolve first (cheap), HTTP only when the
  /// address is real. Never throws — a broken layer reads as blocked here,
  /// and the control chain decides whether that means anything at all.
  static Future<_Chain> _probeHost(
    HostResolver resolve,
    UrlProber probe,
    String host,
    Uri url,
  ) async {
    List<InternetAddress>? addrs;
    try {
      addrs = await resolve(host);
    } catch (_) {
      addrs = null;
    }
    if (addrs == null || _sinkholed(addrs)) return const _Chain();
    var reachable = false;
    try {
      reachable = await probe(url);
    } catch (_) {
      reachable = false;
    }
    return _Chain(dns: true, http: reachable);
  }

  /// A filter answers blocked hosts with a sinkhole (AdGuard's `0.0.0.0`,
  /// a local proxy's loopback) — a "successful" lookup that leads nowhere.
  static bool _sinkholed(List<InternetAddress> addrs) =>
      addrs.isEmpty ||
      addrs.every(
        (a) => a.isLoopback || a.address == '0.0.0.0' || a.address == '::',
      );

  // ------------------------------------------------------------ real probes

  static Future<List<InternetAddress>?> _resolve(String host) async {
    try {
      return await InternetAddress.lookup(host).timeout(
        const Duration(milliseconds: 2500),
      );
    } catch (_) {
      // NXDOMAIN, blocked resolution, timeout — all read as "no address".
      return null;
    }
  }

  /// Any HTTP status means the host is reachable (the endpoint isn't a
  /// health page — a 404 still proves no filter stood in the way).
  static Future<bool> _probe(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 2500);
    try {
      final request = await client.getUrl(url).timeout(
        const Duration(milliseconds: 2500),
      );
      final response = await request.close().timeout(
        const Duration(milliseconds: 2500),
      );
      return response.statusCode > 0;
    } catch (_) {
      // Refused, reset, timed out — a filter (or no route) ate it.
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// The device's Private DNS hostname, only when it is set to a custom
  /// server (`mode == 'hostname'`). Null otherwise — fail open, and never
  /// a standalone trigger.
  static Future<String?> _privateDns() async {
    try {
      final raw = await Security.channel.invokeMethod<Object>('getPrivateDns');
      if (raw is! Map || raw['mode'] != 'hostname') return null;
      final spec = raw['specifier'];
      return spec is String && spec.isNotEmpty ? spec : null;
    } catch (_) {
      // Missing plugin / locked-down ROM — skip the enrichment.
      return null;
    }
  }
}

/// DNS + HTTP outcome for a single host.
class _Chain {
  const _Chain({this.dns = false, this.http = false});

  final bool dns;
  final bool http;
}

/// User-facing reason for an ad-blocker flag, or the raw flag when unknown.
String adblockReason(String flag) {
  if (flag.startsWith('dns:')) {
    return '${flag.substring(4)} is blocked by a DNS filter';
  }
  if (flag.startsWith('http:')) {
    return '${flag.substring(5)} is blocked by a network filter '
        '(VPN or firewall)';
  }
  if (flag.startsWith('private-dns:')) {
    return 'Private DNS is set to ${flag.substring(12)}';
  }
  if (flag == 'offline') return 'No internet connection to verify ads';
  return flag.replaceAll('-', ' ');
}
