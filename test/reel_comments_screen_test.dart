import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/reel_comments_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

ReelComment _comment(String text) => ReelComment(
  id: text,
  text: text,
  createdAt: '',
  user: PublicUser(
    id: '42',
    displayName: 'Jeric',
    username: 'jeric',
    createdAt: '',
    followerCount: 0,
    followingCount: 0,
    reelCount: 0,
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<ReelComment>> Function(int) load,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: ReelCommentsScreen(reelId: 'r1', load: load),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('loads comments when opened', (tester) async {
    await _pump(tester, load: (_) async => [_comment('Nice')]);
    expect(find.text('Nice'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows empty state after initial load', (tester) async {
    await _pump(tester, load: (_) async => const []);
    expect(find.text('No comments yet'), findsOneWidget);
  });

  testWidgets('shows retry after load failure and recovers', (tester) async {
    var fail = true;
    await _pump(
      tester,
      load: (_) async {
        if (fail) throw Exception('offline');
        return [_comment('Recovered')];
      },
    );
    expect(find.text('Could not load comments'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Recovered'), findsOneWidget);
  });
}
