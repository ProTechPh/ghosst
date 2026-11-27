import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/referral_sheet.dart';
import 'package:ghosst/services/worker_backend.dart';

void main() {
  test('normalizes a referral code and rejects malformed ones', () {
    expect(Backend.normalizeReferralCode(' ref-abcd23 '), 'REF-ABCD23');
    expect(Backend.normalizeReferralCode('REF-000000'), '');
    expect(Backend.normalizeReferralCode(''), '');
    expect(Backend.normalizeReferralCode('REF-ABCDEFG'), '');
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
