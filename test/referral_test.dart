import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/worker_backend.dart';

void main() {
  test('normalizes a referral code and rejects malformed ones', () {
    expect(Backend.normalizeReferralCode(' ref-abcd23 '), 'REF-ABCD23');
    expect(Backend.normalizeReferralCode('REF-000000'), '');
    expect(Backend.normalizeReferralCode(''), '');
    expect(Backend.normalizeReferralCode('REF-ABCDEFG'), '');
  });
}
