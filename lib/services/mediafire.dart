import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Resolves MediaFire share pages to a direct download URL.
///
/// MediaFire's file page is plain server-rendered HTML (no JS challenge), so
/// a two-step scrape works reliably:
///
///  1. `GET /file/<quickkey>/<name>/file` → find the `?dkey=` download anchor.
///  2. `GET` that anchor → the page embeds the real
///     `https://download<host>.mediafire.com/...` direct link.
///
/// If [url] already points at a `download*.mediafire.com` asset (or at a
/// non-MediaFire host) it is returned unchanged so admins can paste direct
/// links or third-party hosting links too.
class MediaFire {
  MediaFire._();

  /// Browser UA MediaFire expects (bare UJs get a different page).
  static const ua =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static const _timeout = Duration(seconds: 20);

  /// True when [url] looks like a MediaFire share page that needs resolving.
  static bool needsResolve(String url) {
    final u = url.trim().toLowerCase();
    if (u.isEmpty) return false;
    if (!u.contains('mediafire.com')) return false;
    // Already a direct CDN link (download*.mediafire.com/...).
    if (RegExp(r'https://download\d*\.mediafire\.com/').hasMatch(u)) {
      return false;
    }
    // Folder / landing pages without a file key can't be resolved to a file.
    return u.contains('/file/');
  }

  /// Returns the direct download URL for a MediaFire link.
  /// Throws [MediaFireException] when the page can't be resolved.
  static Future<String> resolveDirectUrl(String url) async {
    final input = url.trim();
    if (input.isEmpty) throw const MediaFireException('Empty link');
    if (!needsResolve(input)) return input;

    final client = HttpClient()..userAgent = ua;
    try {
      // ---- step 1: file page → dkey anchor --------------------------------
      final page = await _get(client, input);
      final dkey = RegExp(
        r'href="(//www\.mediafire\.com/file/[^"\s]+\?dkey=[^"]+)"',
      ).firstMatch(page);
      if (dkey == null) {
        throw const MediaFireException('Download not found — try again later');
      }

      // ---- step 2: dkey page → direct CDN url ----------------------------
      final hop = 'https:${dkey.group(1)!.replaceAll('&amp;', '&')}';
      final page2 = await _get(client, hop);
      final direct = RegExp(
        r'https://download\d*\.mediafire\.com/[^"\x27\s\\]+',
      ).firstMatch(page2);
      if (direct == null) {
        throw const MediaFireException(
          'This download link expired or is invalid',
        );
      }
      return direct.group(0)!.replaceAll('&amp;', '&');
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _get(HttpClient client, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const MediaFireException('Invalid download link');
    }
    final req = await client.getUrl(uri).timeout(_timeout);
    req.followRedirects = true;
    req.maxRedirects = 6;
    final res = await req.close().timeout(_timeout);
    final body = await res
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(_timeout);
    if (res.statusCode >= 400) {
      throw MediaFireException(
        'Download service error (HTTP ${res.statusCode})',
      );
    }
    return body;
  }
}

class MediaFireException implements Exception {
  const MediaFireException(this.message);
  final String message;

  @override
  String toString() => message;
}
