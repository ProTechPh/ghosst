import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/api_exception.dart';
import 'package:ghosst/screens/direct_chat_screen.dart' show ReportContent;
import 'package:ghosst/screens/reels_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

Reel _reel(String id, String name, {int imageCount = 1, bool isMine = false}) =>
    Reel(
      id: id,
      caption: 'Caption $id',
      posterUrl: 'https://example.com/$id-1.jpg',
      images: [
        for (var i = 1; i <= imageCount; i++)
          ReelImage(
            position: i,
            url: 'https://example.com/$id-$i.jpg',
            sha256: 'a' * 64,
            sizeBytes: 1,
            mimeType: 'image/jpeg',
          ),
      ],
      createdAt: '',
      creator: PublicUser(
        id: name,
        displayName: name,
        username: name.toLowerCase(),
        createdAt: '',
        followerCount: 0,
        followingCount: 0,
        reelCount: 0,
      ),
      likeCount: 0,
      commentCount: 0,
      isMine: isMine,
    );

Future<void> _pump(
  WidgetTester tester, {
  required Future<ReelFeedPage> Function(String, int) load,
  Future<void> Function(String)? onLike,
  Future<void> Function(String)? onUnlike,
  ValueChanged<String>? onOpenProfile,
  ReportContent? onReport,
  VoidCallback? onOpenUpload,
  Future<void> Function(String)? onDeleteReel,
  bool active = true,
  int coins = 0,
  VoidCallback? onOpenWallet,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ReelsScreen(
          key: UniqueKey(),
          load: load,
          onLike: onLike,
          onUnlike: onUnlike,
          onOpenProfile: onOpenProfile,
          onReport: onReport,
          onOpenUpload: onOpenUpload,
          onDeleteReel: onDeleteReel,
          active: active,
          coins: coins,
          onOpenWallet: onOpenWallet,
          loadComments: (_, __) async => const [],
          submitComment: (_, __) async {},
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('inactive tab loads on first activation', (tester) async {
    final key = GlobalKey();
    var calls = 0;
    Future<ReelFeedPage> loader(_, __) async {
      calls++;
      return ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1);
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ReelsScreen(key: key, active: false, load: loader),
        ),
      ),
    );
    await tester.pump();
    expect(calls, 0);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ReelsScreen(key: key, active: true, load: loader),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, 1);
    expect(find.text('Caption r1'), findsOneWidget);
  });

  testWidgets('stale feed responses cannot replace the selected feed', (
    tester,
  ) async {
    final first = Completer<ReelFeedPage>();
    final second = Completer<ReelFeedPage>();
    var calls = 0;
    await _pump(
      tester,
      load: (feed, _) {
        calls++;
        return feed == 'for-you' ? first.future : second.future;
      },
    );
    await tester.tap(find.text('Following'));
    await tester.pump();
    second.complete(
      ReelFeedPage(reels: [_reel('following', 'Followed')], nextOffset: 1),
    );
    await _settle(tester);
    expect(find.text('Caption following'), findsOneWidget);
    first.complete(
      ReelFeedPage(reels: [_reel('stale', 'Stale')], nextOffset: 1),
    );
    await _settle(tester);
    expect(calls, 2);
    expect(find.text('Caption following'), findsOneWidget);
    expect(find.text('Caption stale'), findsNothing);
  });

  testWidgets('owner can delete a reel', (tester) async {
    final owned = _reel('mine', 'Me', isMine: true);
    String? deleted;
    await _pump(
      tester,
      load: (_, __) async {
        if (deleted != null) {
          return const ReelFeedPage(reels: [], nextOffset: 0);
        }
        return ReelFeedPage(reels: [owned], nextOffset: 1);
      },
      onDeleteReel: (id) async => deleted = id,
    );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('reel-delete-mine')));
    await _settle(tester);
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    expect(deleted, 'mine');
    expect(find.text('No reels yet'), findsOneWidget);
  });

  testWidgets('segments, like, comments, profile, and report actions work', (
    tester,
  ) async {
    String? liked;
    String? unliked;
    String? profile;
    String? report;
    await _pump(
      tester,
      load: (_, __) async =>
          ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1),
      onLike: (id) async => liked = id,
      onUnlike: (id) async => unliked = id,
      onOpenProfile: (id) => profile = id,
      onReport:
          ({
            required targetType,
            required targetId,
            required reason,
            details = '',
            snapshot,
            threadId,
          }) async {
            report = '$targetType:$targetId';
          },
    );
    await _settle(tester);

    expect(find.text('For You'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reel-like-r1')));
    await tester.pump();
    expect(liked, 'r1');
    await tester.tap(find.byKey(const ValueKey('reel-like-r1')));
    await tester.pump();
    expect(unliked, 'r1');

    await tester.tap(find.byKey(const ValueKey('reel-comments-r1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Comments'), findsOneWidget);
    await tester.pageBack();
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('reel-profile-One')));
    expect(profile, 'One');

    await tester.tap(find.byKey(const ValueKey('reel-report-r1')));
    await _settle(tester);
    expect(find.text('Report reel'), findsOneWidget);
    await tester.tap(find.text('Submit report'));
    await _settle(tester);
    expect(report, 'reel:r1');
  });

  testWidgets('carousel renders dots and horizontal swipe changes image', (
    tester,
  ) async {
    await _pump(
      tester,
      load: (_, __) async => ReelFeedPage(
        reels: [_reel('r1', 'One', imageCount: 3)],
        nextOffset: 1,
      ),
    );
    await _settle(tester);
    expect(find.byKey(const ValueKey('reel-image-r1-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('reel-dot-r1-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('reel-dot-r1-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('reel-dot-r1-2')), findsOneWidget);
    final firstDot = tester.widget<Semantics>(
      find.byKey(const ValueKey('reel-dot-semantics-r1-0')),
    );
    final secondDot = tester.widget<Semantics>(
      find.byKey(const ValueKey('reel-dot-semantics-r1-1')),
    );
    expect(firstDot.properties.label, 'Image 1 of 3');
    expect(firstDot.properties.selected, isTrue);
    expect(secondDot.properties.selected, isFalse);

    await tester.drag(
      find.byKey(const ValueKey('reel-carousel-r1')),
      const Offset(-400, 0),
    );
    await _settle(tester);
    expect(find.byKey(const ValueKey('reel-image-r1-2')), findsOneWidget);
    final selectedDot = tester.widget<Semantics>(
      find.byKey(const ValueKey('reel-dot-semantics-r1-1')),
    );
    expect(selectedDot.properties.selected, isTrue);
  });

  testWidgets('empty and error states support Retry', (tester) async {
    await _pump(
      tester,
      load: (_, __) async => const ReelFeedPage(reels: [], nextOffset: 0),
    );
    await _settle(tester);
    expect(find.text('No reels yet'), findsOneWidget);

    var fail = true;
    await _pump(
      tester,
      load: (_, __) async {
        if (fail) throw Exception('offline');
        return ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1);
      },
    );
    await _settle(tester);
    expect(find.text('Could not load reels'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await _settle(tester);
    expect(find.text('Caption r1'), findsOneWidget);
  });

  testWidgets('embedded home shows wallet balance without an upload FAB', (
    tester,
  ) async {
    String? wallet;
    var uploadCalls = 0;
    await _pump(
      tester,
      load: (_, __) async =>
          ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1),
      coins: 250,
      onOpenWallet: () => wallet = 'opened',
      onOpenUpload: () => uploadCalls++,
    );
    await _settle(tester);

    expect(find.text('250'), findsOneWidget);
    await tester.tap(find.text('250'));
    expect(wallet, 'opened');
    expect(find.byTooltip('Upload reel'), findsNothing);
    expect(uploadCalls, 0);
  });

  testWidgets('unconfigured feed shows unavailable without upload', (
    tester,
  ) async {
    await _pump(
      tester,
      load: (_, __) async => throw const ApiException(
        kind: ApiErrorKind.server,
        message: 'not configured',
        code: 'reels_not_configured',
      ),
      onOpenUpload: () {},
    );
    await _settle(tester);
    expect(find.text('Reels unavailable'), findsOneWidget);
    expect(find.byTooltip('Upload reel'), findsNothing);
  });

  testWidgets('initial reel from a later page is prepended and selected', (
    tester,
  ) async {
    final selected = _reel('selected', 'Creator');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ReelsScreen(
            embedded: false,
            initialReelId: selected.id,
            load: (_, __) async => ReelFeedPage(
              reels: [_reel('r1', 'Other'), selected],
              nextOffset: 2,
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('Caption selected'), findsOneWidget);
  });
}
