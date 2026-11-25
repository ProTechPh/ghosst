import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/user_profile_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

PublicUser _user({
  String id = '42',
  String displayName = 'Jeric',
  String username = 'jeric',
  String createdAt = '2026-01-01T00:00:00.000Z',
  bool isAdmin = false,
  bool isModerator = false,
  bool isFollowing = false,
  bool isSelf = false,
  int followerCount = 12,
}) => PublicUser(
  id: id,
  displayName: displayName,
  username: username,
  createdAt: createdAt,
  isAdmin: isAdmin,
  isModerator: isModerator,
  followerCount: followerCount,
  followingCount: 7,
  reelCount: 3,
  isFollowing: isFollowing,
  isSelf: isSelf,
);

Future<void> _pump(
  WidgetTester tester, {
  required Future<PublicUser> Function(String id) loader,
  Future<bool> Function(String id)? loadBlocked,
  ValueChanged<PublicUser>? onMessage,
  VoidCallback? onReport,
  Future<bool> Function()? onBlock,
  Future<bool> Function()? onUnblock,
  Future<FollowState> Function(String id)? onFollow,
  Future<FollowState> Function(String id)? onUnfollow,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: UserProfileScreen(
          userId: '42',
          loader: loader,
          loadBlocked: loadBlocked ?? ((_) async => false),
          onMessage: onMessage ?? (_) {},
          onReport: onReport ?? () {},
          onBlock: onBlock,
          onUnblock: onUnblock,
          onFollow: onFollow,
          onUnfollow: onUnfollow,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders safe identity, badges, join date, and stats', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: (_) async => _user(isAdmin: true, isModerator: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jeric'), findsOneWidget);
    expect(find.text('@jeric'), findsOneWidget);
    expect(find.text('ADMIN'), findsOneWidget);
    expect(find.text('MODERATOR'), findsOneWidget);
    expect(find.text('Member since January 2026'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('No reels yet'), findsOneWidget);
  });

  testWidgets('uses initials and member fallback when identity is blank', (
    tester,
  ) async {
    await _pump(
      tester,
      loader: (_) async => _user(displayName: '', username: ''),
    );
    await tester.pumpAndSettle();

    expect(find.text('Member #42'), findsWidgets);
    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('follow is optimistic, updates count, and disables in flight', (
    tester,
  ) async {
    final result = Completer<FollowState>();
    await _pump(
      tester,
      loader: (_) async => _user(),
      onFollow: (_) => result.future,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Follow'));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Following'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Following'))
          .onPressed,
      isNull,
    );

    result.complete(const FollowState(isFollowing: true, followerCount: 13));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Following'), findsOneWidget);
  });

  testWidgets('failed follow rolls back and offers Retry', (tester) async {
    await _pump(
      tester,
      loader: (_) async => _user(),
      onFollow: (_) async => throw Exception('offline'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Follow'));
    await tester.pumpAndSettle();
    expect(find.text('Follow'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('self profile hides Follow', (tester) async {
    await _pump(
      tester,
      loader: (_) async => _user(isSelf: true),
      onFollow: (_) async =>
          const FollowState(isFollowing: true, followerCount: 13),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Follow'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Following'), findsNothing);
  });

  testWidgets('message and report actions invoke callbacks', (tester) async {
    var messaged = false;
    var reported = false;
    await _pump(
      tester,
      loader: (_) async => _user(),
      onMessage: (user) => messaged = true,
      onReport: () => reported = true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Message'));
    expect(messaged, isTrue);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report user'));
    expect(reported, isTrue);
  });

  testWidgets('block action invokes callback after confirmation', (
    tester,
  ) async {
    var blocked = false;
    await _pump(
      tester,
      loader: (_) async => _user(),
      onBlock: () async => blocked = true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block user'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(blocked, isTrue);
  });

  testWidgets('blocked profile offers Unblock', (tester) async {
    var unblocked = false;
    await _pump(
      tester,
      loader: (_) async => _user(),
      loadBlocked: (_) async => true,
      onUnblock: () async => unblocked = true,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unblock user'));
    expect(unblocked, isTrue);
  });

  testWidgets('profile renders while block state is still loading', (
    tester,
  ) async {
    final blocked = Completer<bool>();
    await _pump(
      tester,
      loader: (_) async => _user(),
      loadBlocked: (_) => blocked.future,
    );
    await tester.pumpAndSettle();

    expect(find.text('Jeric'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('failed block does not change the visible state', (tester) async {
    await _pump(
      tester,
      loader: (_) async => _user(),
      onBlock: () async => false,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block user'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();

    expect(find.text('Could not block user. Try again.'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Block user'), findsOneWidget);
  });

  testWidgets('Retry passes the recovered profile to Message', (tester) async {
    var fail = true;
    PublicUser? messaged;
    await _pump(
      tester,
      loader: (_) async {
        if (fail) throw Exception('offline');
        return _user();
      },
      onMessage: (user) => messaged = user,
    );
    await tester.pumpAndSettle();
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Message'));

    expect(messaged?.displayName, 'Jeric');
  });

  testWidgets('loader failure shows Retry and can recover', (tester) async {
    var fail = true;
    await _pump(
      tester,
      loader: (_) async {
        if (fail) throw Exception('offline');
        return _user();
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load profile'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Jeric'), findsOneWidget);
  });

  testWidgets('shows loading until the profile arrives', (tester) async {
    final result = Completer<PublicUser>();
    await _pump(tester, loader: (_) => result.future);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    result.complete(_user());
    await tester.pumpAndSettle();
    expect(find.text('Jeric'), findsOneWidget);
  });
}
