import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/validation.dart';

void main() {
  group('validateEmail', () {
    test('empty is required', () {
      expect(validateEmail(''), 'Email is required');
      expect(validateEmail('   '), 'Email is required');
    });

    test('malformed is rejected', () {
      expect(validateEmail('not-an-email'), 'Enter a valid email address');
      expect(validateEmail('a@b'), 'Enter a valid email address');
      expect(validateEmail('a@b.c'), 'Enter a valid email address');
      expect(validateEmail('a b@c.com'), 'Enter a valid email address');
    });

    test('valid passes', () {
      expect(validateEmail('user@test.com'), isNull);
      expect(validateEmail('  user@test.co  '), isNull);
      expect(validateEmail('a@b.co'), isNull);
    });
  });

  group('validatePassword', () {
    test('empty is required', () {
      expect(validatePassword(''), 'Password is required');
    });

    test('256-char cap always applies', () {
      expect(validatePassword('a' * 257),
          'Password must be 256 characters or fewer');
      expect(validatePassword('a' * 256), isNull);
    });

    test('register enforces 8-char minimum only when asked', () {
      expect(validatePassword('short', enforceLength: true),
          'Use at least 8 characters');
      expect(validatePassword('short'), isNull);
      expect(validatePassword('12345678', enforceLength: true), isNull);
      expect(validatePassword('hunter2', enforceLength: true),
          'Use at least 8 characters');
    });
  });
}
