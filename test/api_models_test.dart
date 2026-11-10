import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/api_backend.dart';

void main() {
  group('ApiProduct.fromJson', () {
    test('full payload maps through', () {
      final p = ApiProduct.fromJson({
        'id': 'p1',
        'name': 'Key pack',
        'cost': 250,
        'active': false,
        'description': 'desc',
        'imageUrls': ['https://cdn/x.png', 'https://cdn/y.png'],
        'youtubeUrl': 'https://youtube/x',
        'type': 'apk',
        'version': '1.2.3',
        'fileSize': '12 MB',
        'durations': [
          {'label': '7d', 'cost': 100},
          {'label': '30d', 'cost': 300.0},
          'not-a-map',
        ],
        'availableCount': 5,
      });

      expect(p.id, 'p1');
      expect(p.cost, 250);
      expect(p.active, isFalse);
      expect(p.imageUrls, hasLength(2));
      expect(p.isKey, isFalse);
      expect(p.isDownloadable, isTrue);
      expect(p.hasDurations, isTrue);
      expect(p.durations, hasLength(2));
      expect(p.durations[1].cost, 300);
      expect(p.availableCount, 5);
    });

    test('missing fields fall back, never throw', () {
      final p = ApiProduct.fromJson({'id': 'p1'});
      expect(p.name, '');
      expect(p.cost, 0);
      expect(p.active, isTrue);
      expect(p.type, 'key');
      expect(p.isKey, isTrue);
      expect(p.imageUrls, isEmpty);
      expect(p.durations, isEmpty);
      expect(p.hasDurations, isFalse);
    });
  });

  group('ApiClaim.fromJson', () {
    test('parses timestamps and flags', () {
      final c = ApiClaim.fromJson({
        'id': 'c1',
        'productId': 'p1',
        'productName': 'X',
        'keyText': 'app',
        'cost': 99,
        'duration': '30d',
        'isDownload': true,
        'createdAt': '2026-01-02T03:04:05Z',
        'sha256': 'abc',
      });
      expect(c.cost, 99);
      expect(c.duration, '30d');
      expect(c.isDownload, isTrue);
      expect(c.createdAt, DateTime.parse('2026-01-02T03:04:05Z'));
      expect(c.sha256, 'abc');
    });

    test('invalid date becomes null instead of throwing', () {
      final c = ApiClaim.fromJson({'id': 'c1', 'createdAt': 'not-a-date'});
      expect(c.createdAt, isNull);
      expect(c.isDownload, isFalse);
    });
  });
}
