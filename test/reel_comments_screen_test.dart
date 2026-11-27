import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/reel_comments_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

ReelComment _comment(
  String text, {
  String name = 'Jeric',
  String createdAt = '',
  String? avatarUrl,
  String parentId = '',
  String replyTo = '',
}) => ReelComment(
  id: text,
  text: text,
  parentId: parentId,
  replyTo: replyTo,
  createdAt: createdAt,
  user: PublicUser(
    id: '42',
    displayName: name,
    username: name.toLowerCase(),
    avatarUrl: avatarUrl,
    createdAt: '',
    followerCount: 0,
    followingCount: 0,
    reelCount: 0,
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<ReelComment>> Function(int) load,
  Future<void> Function(String)? submit,
  Future<void> Function(String parentId, String text)? submitReply,
  ValueChanged<String>? onOpenProfile,
  Size size = const Size(800, 600),
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(size: size, viewInsets: viewInsets),
        child: Scaffold(
          body: ReelCommentsScreen(
            reelId: 'r1',
            load: load,
            submit: submit,
            submitReply: submitReply,
            onOpenProfile: onOpenProfile,
          ),
        ),
      ),
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

  testWidgets('comment avatar shows image and opens the profile', (
    tester,
  ) async {
    String? opened;
    await _pump(
      tester,
      load: (_) async => [
        _comment(
          'Nice',
          avatarUrl: 'https://example.com/avatar.jpg',
        ),
      ],
      onOpenProfile: (id) => opened = id,
    );

    expect(find.byKey(const ValueKey('comment-profile-Nice')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('comment-profile-Nice')));
    await tester.pump();
    expect(opened, '42');
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

  testWidgets('comments sheet uses TikTok chrome and keeps composer actions', (
    tester,
  ) async {
    const longText =
        'A very long comment that should wrap inside the narrow comments sheet '
        'without pushing the composer off screen';
    final submitted = <String>[];
    await _pump(
      tester,
      size: const Size(320, 640),
      load: (_) async => [
        _comment(
          longText,
          name: 'VeryLongDisplayNameForComments',
          createdAt: '2026-11-20T10:00:00.000Z',
        ),
      ],
      submit: (text) async => submitted.add(text),
    );

    expect(find.byKey(const ValueKey('reel-comments-handle')), findsOneWidget);
    expect(find.text('Comments'), findsOneWidget);
    expect(find.text('VeryLongDisplayNameForComments'), findsOneWidget);
    expect(find.text(longText), findsOneWidget);
    expect(
      find.byKey(ValueKey('comment-reply-$longText')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('reel-comments-composer')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('reel-comments-send'))).height,
      greaterThanOrEqualTo(48),
    );
    for (var i = 0; i < 3; i++) {
      expect(
        find.byKey(ValueKey('reel-comments-emoji-$i')),
        findsOneWidget,
      );
    }

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byKey(const ValueKey('reel-comments-send')));
    await tester.pump();
    expect(submitted, ['hello']);

    await _pump(
      tester,
      size: const Size(320, 640),
      load: (_) async => [_comment('Draft')],
      submit: (_) async => throw StateError('offline'),
    );
    await tester.enterText(find.byType(TextField), 'try again');
    await tester.tap(find.byKey(const ValueKey('reel-comments-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('try again'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('reel-comments-sheet')),
        matching: find.text('Could not post comment. Try again.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('composer stays above the keyboard', (tester) async {
    await _pump(
      tester,
      size: const Size(320, 640),
      viewInsets: const EdgeInsets.only(bottom: 200),
      load: (_) async => [
        for (var i = 0; i < 20; i++) _comment('Comment $i'),
      ],
    );
    final composerBottom = tester.getBottomRight(
      find.byKey(const ValueKey('reel-comments-composer')),
    ).dy;
    expect(composerBottom, lessThanOrEqualTo(640 - 200));
  });

  testWidgets('reply action sets a target and submits with parentId', (
    tester,
  ) async {
    String? plain;
    String? replyParent;
    String? replyText;
    var replyCalls = 0;
    await _pump(
      tester,
      load: (_) async => [_comment('Nice')],
      submit: (text) async => plain = text,
      submitReply: (parent, text) async {
        replyParent = parent;
        replyText = text;
        replyCalls++;
      },
    );

    await tester.tap(find.byKey(const ValueKey('comment-reply-Nice')));
    await tester.pump();
    expect(find.byKey(const ValueKey('comment-reply-banner')), findsOneWidget);
    expect(find.textContaining('@Jeric'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byKey(const ValueKey('reel-comments-send')));
    await tester.pumpAndSettle();

    expect(replyCalls, 1);
    expect(replyParent, 'Nice');
    expect(replyText, 'hello');
    expect(plain, isNull);
  });

  testWidgets('cancel clears the reply target', (tester) async {
    String? plain;
    var replyCalls = 0;
    await _pump(
      tester,
      load: (_) async => [_comment('Nice')],
      submit: (text) async => plain = text,
      submitReply: (parent, text) async => replyCalls++,
    );

    await tester.tap(find.byKey(const ValueKey('comment-reply-Nice')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('comment-reply-cancel')));
    await tester.pump();
    expect(find.byKey(const ValueKey('comment-reply-banner')), findsNothing);

    await tester.enterText(find.byType(TextField), 'plain');
    await tester.tap(find.byKey(const ValueKey('reel-comments-send')));
    await tester.pumpAndSettle();
    expect(plain, 'plain');
    expect(replyCalls, 0);
  });

  testWidgets('inline reply label uses server replyTo', (tester) async {
    await _pump(
      tester,
      load: (_) async => [_comment('Nice reply', replyTo: 'Jeric')],
    );
    expect(
      find.byKey(const ValueKey('comment-reply-label-Nice reply')),
      findsOneWidget,
    );
    expect(find.text('Replying to @Jeric'), findsOneWidget);
  });

  testWidgets('missing submitReply falls back to plain submit', (tester) async {
    String? plain;
    await _pump(
      tester,
      load: (_) async => [_comment('Nice')],
      submit: (text) async => plain = text,
    );
    await tester.tap(find.byKey(const ValueKey('comment-reply-Nice')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'still plain');
    await tester.tap(find.byKey(const ValueKey('reel-comments-send')));
    await tester.pumpAndSettle();
    expect(plain, 'still plain');
  });
}
