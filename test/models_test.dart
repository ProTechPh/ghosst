import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/models.dart';

void main() {
  group('productTypeOf', () {
    test('maps raw strings, defaults to key', () {
      expect(productTypeOf('apk'), ProductType.apk);
      expect(productTypeOf('file'), ProductType.file);
      expect(productTypeOf('key'), ProductType.key);
      expect(productTypeOf(null), ProductType.key);
      expect(productTypeOf(''), ProductType.key);
      expect(productTypeOf('APP'), ProductType.key);
    });
  });

  group('Product', () {
    Product p({String type = 'key', List<ProductDuration> durations = const []}) =>
        Product(
            id: 'p1',
            name: 'X',
            cost: 100,
            active: true,
            type: type,
            durations: durations);

    test('type helpers', () {
      expect(p().isKey, isTrue);
      expect(p(type: 'apk').isApk, isTrue);
      expect(p(type: 'file').isFile, isTrue);
      expect(p(type: 'apk').isDownloadable, isTrue);
      expect(p().isDownloadable, isFalse);
    });

    test('hasDurations mirrors the list', () {
      expect(p().hasDurations, isFalse);
      expect(
          p(durations: const [ProductDuration(label: '7d', cost: 50)])
              .hasDurations,
          isTrue);
    });
  });

  group('StockEntry.claimed', () {
    test('only available is unclaimed', () {
      StockEntry s(String status) => StockEntry(
          keyId: 'k1', productId: 'p1', keyText: 'KEY', status: status);
      expect(s('available').claimed, isFalse);
      expect(s('claimed').claimed, isTrue);
      expect(s('').claimed, isTrue);
    });
  });

  group('StockWriteResult', () {
    test('ok when nothing failed', () {
      const r = StockWriteResult(added: 3, failed: 0, skipped: 1);
      expect(r.ok, isTrue);
      const bad = StockWriteResult(added: 1, failed: 2);
      expect(bad.ok, isFalse);
    });
  });

  group('Announcement.fromJson', () {
    test('parses and defaults missing fields', () {
      final a = Announcement.fromJson(
          {'id': 'a1', 'title': 'Hi', 'body': 'Body', 'createdAt': 'now'});
      expect(a.id, 'a1');
      expect(a.title, 'Hi');
      expect(a.body, 'Body');
      expect(a.createdAt, 'now');

      final empty = Announcement.fromJson(const <String, dynamic>{});
      expect(empty.id, '');
      expect(empty.title, '');
      expect(empty.body, '');
    });
  });

  group('MutedUser / BannedWord / Moderation', () {
    test('MutedUser reads displayName', () {
      final m =
          MutedUser.fromJson({'id': 'u1', 'displayName': 'Ana', 'email': 'a@b.co'});
      expect(m.name, 'Ana');
      expect(m.email, 'a@b.co');
    });

    test('BannedWord coerces numeric id', () {
      expect(BannedWord.fromJson({'id': 7, 'word': 'spam'}).id, 7);
      expect(BannedWord.fromJson({'id': 7.0, 'word': 'spam'}).id, 7);
      expect(BannedWord.fromJson(const <String, dynamic>{}).id, 0);
    });

    test('Moderation defaults', () {
      final d = Moderation.fromJson(const <String, dynamic>{});
      expect(d.blockLinks, isFalse);
      expect(d.muteHours, 24);
      final s = Moderation.fromJson({'blockLinks': true, 'muteHours': 2});
      expect(s.blockLinks, isTrue);
      expect(s.muteHours, 2);
    });
  });

  group('unreadAnnouncement', () {
    const a = Announcement(id: 'a1', title: 'T', body: 'B');
    test('null and dismissed are hidden', () {
      expect(unreadAnnouncement(null, ''), isNull);
      expect(unreadAnnouncement(a, 'a1'), isNull);
      expect(unreadAnnouncement(a, ''), same(a));
      expect(unreadAnnouncement(a, 'other'), same(a));
    });
  });
}
