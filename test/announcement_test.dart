import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/models.dart';

void main() {
  Announcement sample() => const Announcement(
    id: 'a1',
    title: 'Bagong stock',
    body: 'Netflix — 1 Month',
  );

  test('parses the API payload', () {
    final a = Announcement.fromJson({
      'id': 'a1',
      'title': 'Bagong stock',
      'body': 'Netflix — 1 Month',
      'createdAt': '2026-11-03 10:00:00',
    });
    expect(a.id, 'a1');
    expect(a.body, 'Netflix — 1 Month');
    expect(a.createdAt, '2026-11-03 10:00:00');
  });

  test('missing fields do not throw', () {
    final a = Announcement.fromJson({'id': 'x'});
    expect(a.title, '');
    expect(a.createdAt, '');
  });

  test('unread only when the id differs from the dismissed one', () {
    expect(unreadAnnouncement(sample(), ''), isNotNull);
    expect(unreadAnnouncement(sample(), 'other'), isNotNull);
    expect(unreadAnnouncement(sample(), 'a1'), isNull);
    expect(unreadAnnouncement(null, ''), isNull);
  });
}
