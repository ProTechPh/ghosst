import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/website_feedback_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

void main() {
  testWidgets('website feedback renders fetched public entries', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: WebsiteFeedbackScreen(
          load: () async => [
            const WebsiteFeedback(
              id: '1',
              username: 'juan',
              comment: 'Great app',
              rating: 5,
              createdAt: '2026-11-26',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('juan'), findsOneWidget);
    expect(find.text('Great app'), findsOneWidget);
    expect(find.byKey(const ValueKey('site-feedback-1')), findsOneWidget);
  });
}
