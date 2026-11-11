/// Extracts the 11-character video id from a YouTube watch / shorts / embed /
/// youtu.be URL (or a bare id). Null when the link isn't a YouTube video.
String? youtubeId(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  // Already a bare 11-character id.
  if (RegExp(r'^[\w-]{11}$').hasMatch(value)) return value;
  final u = Uri.tryParse(value);
  if (u == null) return null;
  final host = u.host.toLowerCase();
  if (host.endsWith('youtu.be')) {
    final seg = u.pathSegments;
    if (seg.isNotEmpty && seg.first.isNotEmpty) return seg.first;
    return null;
  }
  if (host.contains('youtube.com')) {
    if (u.path == '/watch') {
      final v = u.queryParameters['v'];
      if (v != null && v.isNotEmpty) return v;
    }
    final seg = u.pathSegments;
    if (seg.length >= 2 &&
        const ['shorts', 'embed', 'live', 'v'].contains(seg[0]) &&
        seg[1].isNotEmpty) {
      return seg[1];
    }
  }
  return null;
}
