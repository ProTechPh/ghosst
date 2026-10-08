import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Verdict of the cold-start integrity check.
@immutable
class SecurityReport {
  const SecurityReport({required this.blocked, this.flags = const <String>[]});

  /// True when this build must not be allowed in (re-signed, debug, patched).
  final bool blocked;

  /// Raw machine flags from the platform side, e.g. `signature-mismatch`.
  final List<String> flags;

  static const SecurityReport clean = SecurityReport(blocked: false);
}

/// Cold-start tamper check — catches cracked / re-packaged / modded builds.
///
/// The load-bearing signal lives on Android ([MainActivity]): a modified APK
/// is always re-signed with somebody else's key, so the signing certificate
/// alone separates "modified" from "official". This class only marshals the
/// verdict across the channel, times it out, and turns flags into copy a
/// human can read.
///
/// Policy: **fail open**. If the check can't run (debug build, iOS, a ROM
/// that won't answer, a channel that went missing) it reports clean — a
/// broken check must never lock a legitimate user out of the app.
class Security {
  /// Channel shared with `MainActivity.kt`.
  static const MethodChannel channel = MethodChannel(
    'com.astrixtech.ghosst/security',
  );

  /// Reports on this build. Debug/profile builds are signed with the dev
  /// key, so they would flag every local run — release only.
  static Future<SecurityReport> check({
    Duration timeout = const Duration(milliseconds: 3500),
  }) async {
    if (!kReleaseMode) return SecurityReport.clean;
    if (!Platform.isAndroid) return SecurityReport.clean;
    return verifyIntegrity(timeout: timeout);
  }

  /// Marshals the native verdict. Exposed (and channel-driven) so tests can
  /// drive it without going through [check]'s release/OS gate.
  @visibleForTesting
  static Future<SecurityReport> verifyIntegrity({
    Duration timeout = const Duration(milliseconds: 3500),
  }) async {
    Object? raw;
    try {
      raw = await channel
          .invokeMethod<Object>('verifyIntegrity')
          .timeout(timeout);
    } on MissingPluginException {
      return SecurityReport.clean;
    } catch (_) {
      // Timeout, platform exception, hostile build — never brick the launch.
      return SecurityReport.clean;
    }
    if (raw is! Map) return SecurityReport.clean;

    final flags = <String>[];
    final rawFlags = raw['flags'];
    if (rawFlags is List) {
      for (final f in rawFlags) {
        if (f is String && f.isNotEmpty) flags.add(f);
      }
    }
    final blocked = raw['blocked'] == true || flags.isNotEmpty;
    return SecurityReport(blocked: blocked, flags: flags);
  }

  /// Asks Android for the system "Uninstall this app?" sheet.
  ///
  /// A re-signed copy cannot install over the official one, so the modified
  /// build has to go first — this is the one-tap way through that.
  static Future<bool> uninstallSelf() async {
    try {
      final ok = await channel.invokeMethod<bool>('uninstallSelf');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// User-facing reason for a native flag, or the raw flag when unknown.
String securityReason(String flag) {
  if (flag.startsWith('mod-installer:')) {
    return 'Installed through a modding tool';
  }
  switch (flag) {
    case 'signature-mismatch':
      return "App signature doesn't match the official release";
    case 'debuggable-build':
      return 'Debug build — not an official release';
    case 'package-changed':
      return 'App package name was changed';
    default:
      return flag.replaceAll('-', ' ');
  }
}
