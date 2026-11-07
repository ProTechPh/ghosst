import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/chat_service.dart';

void main() {
  group('ChatService.validate', () {
    test('rejects empty text', () {
      expect(ChatService.validate(''), isNotNull);
    });

    test('rejects whitespace-only text', () {
      expect(ChatService.validate('   '), isNotNull);
    });

    test('rejects text longer than 500 chars', () {
      expect(ChatService.validate('x' * 501), isNotNull);
    });

    test('accepts exactly 500 chars', () {
      expect(ChatService.validate('x' * 500), isNull);
    });

    test('accepts trimmed text', () {
      expect(ChatService.validate(' ok '), isNull);
    });
  });

  group('ChatService.fallbackName', () {
    test('uses the display name when present', () {
      expect(ChatService.fallbackName('Jeric', 'abcdef01-2345'), 'Jeric');
    });

    test('derives Anon-<uid6> when the name is blank', () {
      expect(ChatService.fallbackName('', 'abcdef01-2345'), 'Anon-abcdef');
    });

    test('treats a whitespace-only name as blank', () {
      expect(ChatService.fallbackName('   ', 'abcdef01-2345'), 'Anon-abcdef');
    });

    test('truncates a long display name to the 40-char rules cap', () {
      expect(ChatService.fallbackName('x' * 45, 'abcdef01-2345'), 'x' * 40);
    });

    test('never splits a surrogate pair when truncating', () {
      final name = '😀' * 41;
      final out = ChatService.fallbackName(name, 'abcdef01-2345');
      expect(out.runes.length, 40);
      expect(out.runes.every((r) => r == 0x1F600), isTrue);
    });
  });

  group('ChatService.cooldownPassed', () {
    final now = DateTime(2026, 11, 7, 12);

    test('first send always passes', () {
      expect(ChatService.cooldownPassed(null, now), isTrue);
    });

    test('rejects a send inside the 5s window', () {
      expect(ChatService.cooldownPassed(now, now.add(const Duration(seconds: 2))), isFalse);
    });

    test('allows a send after the window', () {
      expect(ChatService.cooldownPassed(now, now.add(const Duration(seconds: 6))), isTrue);
    });
  });
}
