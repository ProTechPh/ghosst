import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/feedback_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  Future<String> Function(String, int)? submit,
  Future<List<AppFeedback>> Function()? loadMine,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: FeedbackScreen(
          key: UniqueKey(),
          submit: submit,
          loadMine: loadMine,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('validates rating and comment before enabling submit', (
    tester,
  ) async {
    await _pump(tester, loadMine: () async => []);
    await tester.pumpAndSettle();

    expect(
      find.text('Feedback is private to the Ghosst team.'),
      findsOneWidget,
    );
    final submit = find.widgetWithText(FilledButton, 'Submit feedback');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Great app!');
    await tester.tap(find.byTooltip('Rate 5 stars'));
    await tester.pump();

    expect(find.text('10/1000'), findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  });

  testWidgets('successful submit shows confirmation and refreshes history', (
    tester,
  ) async {
    var submitted = '';
    var loads = 0;
    await _pump(
      tester,
      submit: (comment, rating) async {
        submitted = '$comment:$rating';
        return '7';
      },
      loadMine: () async {
        loads++;
        return [
          AppFeedback(
            id: '7',
            comment: 'Great app!',
            rating: 5,
            status: 'hidden',
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        ];
      },
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Great app!');
    await tester.tap(find.byTooltip('Rate 5 stars'));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Submit feedback'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Submit feedback'));
    await tester.pumpAndSettle();

    expect(submitted, 'Great app!:5');
    expect(find.text('Thank you for your feedback.'), findsOneWidget);
    expect(find.text('Great app!'), findsOneWidget);
    expect(loads, 2);
  });

  testWidgets('failed submit retains the draft and offers Retry', (
    tester,
  ) async {
    var fail = true;
    await _pump(
      tester,
      submit: (comment, rating) async {
        if (fail) throw Exception('offline');
        return '8';
      },
      loadMine: () async => [],
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Please improve this');
    await tester.tap(find.byTooltip('Rate 4 stars'));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Submit feedback'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Submit feedback'));
    await tester.pumpAndSettle();

    expect(find.text('Please improve this'), findsOneWidget);
    fail = false;
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Thank you for your feedback.'), findsOneWidget);
  });

  testWidgets('history handles empty and error states', (tester) async {
    await _pump(tester, loadMine: () async => []);
    await tester.pumpAndSettle();
    expect(find.text('No feedback submitted yet'), findsOneWidget);

    var fail = true;
    await _pump(
      tester,
      loadMine: () async {
        if (fail) throw Exception('offline');
        return [];
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load feedback history'), findsOneWidget);
    fail = false;
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No feedback submitted yet'), findsOneWidget);
  });

  testWidgets('shows history loading until it arrives', (tester) async {
    final history = Completer<List<AppFeedback>>();
    await _pump(tester, loadMine: () => history.future);
    expect(find.text('Loading feedback…'), findsOneWidget);

    history.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No feedback submitted yet'), findsOneWidget);
  });
}
