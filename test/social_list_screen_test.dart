import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/social_list_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

PublicUser _user(String id, String name) => PublicUser(
  id: id,
  displayName: name,
  username: name.toLowerCase(),
  createdAt: '',
  followerCount: 0,
  followingCount: 0,
  reelCount: 0,
);

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<PublicUser>> Function(int offset) load,
  Future<void> Function(String id)? onOpenProfile,
  SocialListDirection direction = SocialListDirection.followers,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SocialListScreen(
          key: UniqueKey(),
          userId: '42',
          direction: direction,
          load: load,
          onOpenProfile: onOpenProfile,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows title, rows, fallback initials, and opens profiles', (
    tester,
  ) async {
    String? opened;
    await _pump(
      tester,
      load: (_) async => [_user('43', 'Peer')],
      onOpenProfile: (id) async => opened = id,
    );
    await tester.pumpAndSettle();

    expect(find.text('Followers'), findsOneWidget);
    expect(find.text('Peer'), findsOneWidget);
    expect(find.text('P'), findsOneWidget);
    await tester.tap(find.text('Peer'));
    expect(opened, '43');
  });

  testWidgets('loads the next page on scroll and filters duplicates', (
    tester,
  ) async {
    final offsets = <int>[];
    await _pump(
      tester,
      load: (offset) async {
        offsets.add(offset);
        if (offset == 0) {
          return List.generate(20, (i) => _user('$i', 'User $i'));
        }
        return [_user('0', 'User 0'), _user('20', 'User 20')];
      },
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(offsets, [0, 20]);
    expect(find.text('User 20'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(find.text('User 0'), findsOneWidget);
  });

  testWidgets('later page failure shows Retry and preserves loaded rows', (
    tester,
  ) async {
    var failSecond = true;
    await _pump(
      tester,
      load: (offset) async {
        if (offset == 0) {
          return List.generate(20, (i) => _user('$i', 'User $i'));
        }
        if (failSecond) throw Exception('offline');
        return [_user('20', 'User 20')];
      },
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(find.text('Could not load more'), findsOneWidget);
    expect(find.text('User 19'), findsOneWidget);
    failSecond = false;
    final retry = tester.widget<TextButton>(
      find.ancestor(of: find.text('Retry'), matching: find.byType(TextButton)).first,
    );
    retry.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('User 20'), findsOneWidget);
  });

  testWidgets('refreshes after returning from a profile', (tester) async {
    var removed = false;
    await _pump(
      tester,
      load: (_) async => removed ? [] : [_user('43', 'Peer')],
      onOpenProfile: (_) async => removed = true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Peer'));
    await tester.pumpAndSettle();
    expect(find.text('No followers yet'), findsOneWidget);
  });

  testWidgets('empty and error states support Retry', (tester) async {
    await _pump(tester, load: (_) async => []);
    await tester.pumpAndSettle();
    expect(find.text('No followers yet'), findsOneWidget);

    var fail = true;
    await _pump(
      tester,
      load: (_) async {
        if (fail) throw Exception('offline');
        return [_user('43', 'Peer')];
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load followers'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Peer'), findsOneWidget);
  });

  testWidgets('following direction uses its own title and empty copy', (
    tester,
  ) async {
    await _pump(
      tester,
      direction: SocialListDirection.following,
      load: (_) async => [],
    );
    await tester.pumpAndSettle();

    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Not following anyone yet'), findsOneWidget);
  });
}
