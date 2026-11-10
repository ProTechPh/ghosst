import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/notice_screen.dart';

void main() {
  testWidgets('skip unlocks only after the 20 second read window', (
    tester,
  ) async {
    var skipped = false;
    await tester.pumpWidget(
      MaterialApp(home: NoticeScreen(onSkip: () => skipped = true)),
    );

    expect(find.text('Skip for 24 hours'), findsNothing);
    expect(find.textContaining('Close unlocks in'), findsOneWidget);

    await tester.pump(const Duration(seconds: 19));
    expect(find.text('Skip for 24 hours'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Skip for 24 hours'), findsOneWidget);

    await tester.tap(find.text('Skip for 24 hours'));
    await tester.pump();
    expect(skipped, isTrue);
  });
}
