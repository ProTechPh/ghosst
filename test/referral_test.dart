import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/referral_sheet.dart';
import 'package:ghosst/services/worker_backend.dart';

void main() {
  test('normalizes legacy and new referral codes, rejects malformed ones', () {
    expect(Backend.normalizeReferralCode(' ref-abcd23 '), 'REF-ABCD23');
    expect(Backend.normalizeReferralCode('REF-000000'), 'REF-000000');
    expect(Backend.normalizeReferralCode(' abc123 '), 'ABC123');
    expect(Backend.normalizeReferralCode(''), '');
    expect(Backend.normalizeReferralCode('REF-AB'), '');
    expect(Backend.normalizeReferralCode('REF-ABCDEFGHIJKLM'), '');
  });

  test('invite text keeps a legacy referral code as stored', () {
    final text = Backend.referralInviteText(
      referralCode: 'ABC123',
      isPlay: true,
    );
    expect(text, contains('ABC123'));
  });

  test('invite text carries the store link and the referral code', () {
    final play = Backend.referralInviteText(
      referralCode: 'REF-ABC234',
      isPlay: true,
    );
    expect(play, contains('Try Ghosst'));
    expect(
      play,
      contains('https://play.google.com/store/apps/details?id=com.astrixtech.ghosst'),
    );
    expect(play, contains('REF-ABC234'));

    final direct = Backend.referralInviteText(
      referralCode: 'REF-ABC234',
      isPlay: false,
    );
    expect(direct, contains('https://ghossthub.com'));
    expect(direct, isNot(contains('play.google.com')));
    expect(direct, contains('REF-ABC234'));
  });

  testWidgets('referral sheet shows the code and claim controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReferralSheet(
            referralCode: 'REF-ABC234',
            onClaim: (_) async => 100,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('REF-ABC234'), findsOneWidget);
    expect(find.byKey(const Key('referral-code-field')), findsOneWidget);
    expect(find.byKey(const Key('referral-claim-button')), findsOneWidget);
  });

  testWidgets('claim sends a normalized code', (tester) async {
    String captured = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReferralSheet(
            referralCode: 'REF-ABC234',
            onClaim: (code) async {
              captured = code;
              return 100;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const Key('referral-code-field')), ' ref-abc234 ');
    await tester.tap(find.byKey(const Key('referral-claim-button')));
    await tester.pumpAndSettle();

    expect(captured, 'REF-ABC234');
    expect(find.text('Invalid referral code'), findsNothing);
  });

  testWidgets('claim rejects a malformed code without calling the API', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReferralSheet(
            referralCode: 'REF-ABC234',
            onClaim: (_) async {
              calls++;
              return 100;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byKey(const Key('referral-code-field')), 'BAD');
    await tester.tap(find.byKey(const Key('referral-claim-button')));
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Invalid referral code'), findsOneWidget);
  });
}
