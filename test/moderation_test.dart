import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/models.dart';

void main() {
  test('MutedUser parses the API payload', () {
    final u = MutedUser.fromJson({
      'id': 'abc-123',
      'displayName': 'Jeric',
      'email': 'j@x.ph',
    });
    expect(u.id, 'abc-123');
    expect(u.name, 'Jeric');
    expect(u.email, 'j@x.ph');
  });

  test('BannedWord parses the API payload', () {
    final w = BannedWord.fromJson({'id': 7, 'word': 'spam', 'createdAt': '2026-11-07 10:00:00'});
    expect(w.id, 7);
    expect(w.word, 'spam');
  });

  test('Moderation parses the API payload', () {
    final m = Moderation.fromJson({'blockLinks': true, 'muteHours': 6});
    expect(m.blockLinks, isTrue);
    expect(m.muteHours, 6);
  });

  test('missing fields fall back to defaults', () {
    expect(MutedUser.fromJson({}).id, '');
    expect(BannedWord.fromJson({}).id, 0);
    expect(const Moderation().blockLinks, isFalse);
    expect(const Moderation().muteHours, 24);
  });
}
