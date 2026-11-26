import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/api_exception.dart';
import 'package:ghosst/screens/direct_chat_screen.dart' show ReportContent;
import 'package:ghosst/screens/reels_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

Reel _reel(
  String id,
  String name, {
  int imageCount = 1,
  bool isMine = false,
  int likeCount = 0,
  int commentCount = 0,
  bool isFollowing = false,
}) => Reel(
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
  likeCount: likeCount,
  commentCount: commentCount,
  isFollowing: isFollowing,
  isMine: isMine,
);

Future<void> _pump(
  WidgetTester tester, {
  required Future<ReelFeedPage> Function(String, int) load,
  Future<void> Function(String)? onLike,
  Future<void> Function(String)? onUnlike,
  Future<void> Function(String)? onFollow,
  ValueChanged<String>? onOpenProfile,
  ReportContent? onReport,
  VoidCallback? onOpenUpload,
  Future<void> Function(String)? onDeleteReel,
  bool active = true,
  int refreshToken = 0,
  int coins = 0,
  VoidCallback? onOpenWallet,
  VoidCallback? onOpenTutorials,
  VoidCallback? onOpenFeedback,
  Future<List<Tutorial>> Function()? loadTutorials,
  Future<List<WebsiteFeedback>> Function()? loadSiteFeedback,
  ValueChanged<Tutorial>? onOpenTutorial,
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
          onFollow: onFollow,
          onOpenProfile: onOpenProfile,
          onReport: onReport,
          onOpenUpload: onOpenUpload,
          onDeleteReel: onDeleteReel,
          active: active,
          refreshToken: refreshToken,
          coins: coins,
          onOpenWallet: onOpenWallet,
          onOpenTutorials: onOpenTutorials,
          onOpenFeedback: onOpenFeedback,
          loadTutorials: loadTutorials,
          loadSiteFeedback: loadSiteFeedback,
          onOpenTutorial: onOpenTutorial,
          loadComments: (_, _) async => const [],
          submitComment: (_, _) async {},
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
  testWidgets('refresh token reloads the feed after upload or profile change', (
    tester,
  ) async {
    var calls = 0;
    Future<ReelFeedPage> loader(_, _) async {
      calls++;
      return ReelFeedPage(reels: [_reel('r$calls', 'One')], nextOffset: 1);
    }

    await _pump(tester, load: loader);
    await _settle(tester);
    expect(calls, 1);
    expect(find.text('Caption r1'), findsOneWidget);

    await _pump(tester, load: loader, refreshToken: 1);
    await _settle(tester);
    expect(calls, 2);
    expect(find.text('Caption r2'), findsOneWidget);
  });

  testWidgets('inactive tab loads on first activation', (tester) async {
    final key = GlobalKey();
    var calls = 0;
    Future<ReelFeedPage> loader(_, _) async {
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
      load: (_, _) async {
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
      load: (_, _) async =>
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
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Comments'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('reel-profile-One')));
    expect(profile, 'One');

    await tester.tap(find.byKey(const ValueKey('reel-report-r1')));
    await _settle(tester);
    expect(find.text('Report reel'), findsOneWidget);
    await tester.tap(find.text('Submit report'));
    await _settle(tester);
    expect(report, 'reel:r1');
  });

  testWidgets('Reel rail shows full images, counts, and TikTok-style actions', (
    tester,
  ) async {
    String? profile;
    String? liked;
    await _pump(
      tester,
      load: (_, _) async => ReelFeedPage(
        reels: [_reel('r1', 'One', likeCount: 1200, commentCount: 34)],
        nextOffset: 1,
      ),
      onOpenProfile: (id) => profile = id,
      onLike: (id) async => liked = id,
    );
    await _settle(tester);

    final image = tester.widget<CachedNetworkImage>(
      find.byKey(const ValueKey('reel-image-r1-1')),
    );
    expect(image.fit, BoxFit.contain);
    expect(find.text('1.2K'), findsOneWidget);
    expect(find.text('34'), findsOneWidget);
    expect(find.byKey(const ValueKey('reel-follow-badge-r1')), findsOneWidget);

    for (final key in [
      const ValueKey('reel-like-r1'),
      const ValueKey('reel-comments-r1'),
      const ValueKey('reel-report-r1'),
    ]) {
      expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(48));
    }

    await tester.tap(find.byKey(const ValueKey('reel-profile-One')));
    expect(profile, 'One');
    await tester.tap(find.byKey(const ValueKey('reel-like-r1')));
    await _settle(tester);
    expect(liked, 'r1');
    final heart = tester.widget<Icon>(find.byIcon(Icons.favorite));
    expect(heart.color, AppColors.red);

    await _pump(
      tester,
      load: (_, _) async => ReelFeedPage(
        reels: [_reel('mine', 'Me', isMine: true)],
        nextOffset: 1,
      ),
    );
    await _settle(tester);
    expect(find.byKey(const ValueKey('reel-follow-badge-mine')), findsNothing);
  });

  testWidgets('comments open as a modal sheet over the Reel', (tester) async {
    await _pump(
      tester,
      load: (_, _) async =>
          ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1),
    );
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('reel-comments-r1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const ValueKey('reel-image-r1-1')), findsOneWidget);
  });

  testWidgets('like count updates immediately and rolls back on failure', (
    tester,
  ) async {
    await _pump(
      tester,
      load: (_, _) async => ReelFeedPage(
        reels: [_reel('r1', 'One', likeCount: 999)],
        nextOffset: 1,
      ),
      onLike: (id) async {},
    );
    await _settle(tester);
    expect(find.text('999'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reel-like-r1')));
    await _settle(tester);
    expect(find.text('1.0K'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      load: (_, _) async => ReelFeedPage(
        reels: [_reel('r2', 'Two', likeCount: 999)],
        nextOffset: 1,
      ),
      onLike: (id) async => throw StateError('offline'),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('reel-like-r2')));
    await _settle(tester);
    expect(find.text('999'), findsOneWidget);
  });

  testWidgets('plus badge follows backend follow state', (tester) async {
    await _pump(
      tester,
      load: (_, _) async => ReelFeedPage(
        reels: [_reel('r1', 'One', isFollowing: true)],
        nextOffset: 1,
      ),
    );
    await _settle(tester);
    expect(find.byKey(const ValueKey('reel-follow-badge-r1')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      load: (_, _) async => ReelFeedPage(
        reels: [_reel('r2', 'Two', isFollowing: false)],
        nextOffset: 1,
      ),
    );
    await _settle(tester);
    expect(find.byKey(const ValueKey('reel-follow-badge-r2')), findsOneWidget);
  });

  testWidgets('tutorials and feedback are tabs in the same feed', (
    tester,
  ) async {
    String? openedTutorial;
    await _pump(
      tester,
      load: (_, _) async => ReelFeedPage(
        reels: [_reel('r1', 'One')],
        nextOffset: 1,
      ),
      onOpenTutorial: (t) => openedTutorial = t.title,
      loadTutorials: () async => [
        const Tutorial(
          id: 1,
          title: 'How to claim keys',
          slug: 'claim',
          category: 'Guide',
          videoUrl: 'https://youtu.be/abc123',
          content: 'Watch the ad then open your keys.',
          views: 0,
          createdAt: '',
        ),
      ],
      loadSiteFeedback: () async => [
        const WebsiteFeedback(
          id: '1',
          username: 'juan',
          comment: 'Nice app',
          rating: 5,
          createdAt: '',
          imageUrl: 'https://example.com/feedback.jpg',
        ),
      ],
    );
    await _settle(tester);

    final tabs = [
      const ValueKey('reel-feed-tutorials'),
      const ValueKey('reel-feed-feedback'),
      const ValueKey('reel-feed-following'),
      const ValueKey('reel-feed-for-you'),
    ];
    final centers = <double>[];
    for (final key in tabs) {
      expect(find.byKey(key), findsOneWidget);
      centers.add(tester.getCenter(find.byKey(key)).dy);
    }
    for (final label in ['Tutorials', 'Feedback', 'Following', 'For You']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('reels-tabs-scroll')), findsOneWidget);
    expect(centers.every((dy) => (dy - centers.first).abs() < 1), isTrue);

    await tester.tap(find.byKey(const ValueKey('reel-feed-tutorials')));
    await _settle(tester);
    expect(find.text('How to claim keys'), findsOneWidget);
    expect(
      find.text('Watch the ad then open your keys.'),
      findsOneWidget,
    );
    expect(find.byType(CachedNetworkImage), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('reel-tutorial-1')));
    await tester.pump();
    expect(openedTutorial, 'How to claim keys');
    expect(find.byKey(const ValueKey('reel-feed-for-you')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reel-feed-feedback')));
    await _settle(tester);
    expect(find.text('Nice app'), findsOneWidget);
    final feedbackImage = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage).first,
    );
    expect(feedbackImage.imageUrl, 'https://example.com/feedback.jpg');
    expect(feedbackImage.fit, BoxFit.contain);

    await tester.tap(find.byKey(const ValueKey('reel-feed-for-you')));
    await _settle(tester);
    expect(find.text('Caption r1'), findsOneWidget);
  });

  testWidgets('plus badge follows the creator', (tester) async {
    final followed = <String>[];
    await _pump(
      tester,
      load: (_, _) async => ReelFeedPage(
        reels: [_reel('r1', 'One', isFollowing: false)],
        nextOffset: 1,
      ),
      onFollow: (id) async => followed.add(id),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('reel-follow-badge-r1')));
    await _settle(tester);
    expect(followed, ['One']);
    expect(find.byKey(const ValueKey('reel-follow-badge-r1')), findsNothing);
  });

  testWidgets('carousel renders dots and horizontal swipe changes image', (
    tester,
  ) async {
    await _pump(
      tester,
      load: (_, _) async => ReelFeedPage(
        reels: [_reel('r1', 'One', imageCount: 3)],
        nextOffset: 1,
      ),
    );
    await _settle(tester);
    expect(find.byKey(const ValueKey('reel-image-r1-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('reel-dot-r1-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('reel-dot-r1-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('reel-dot-r1-2')), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const ValueKey('reel-dot-r1-1'))).dy,
      greaterThan(
        tester.view.physicalSize.height / tester.view.devicePixelRatio / 2,
      ),
    );
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
      load: (_, _) async => const ReelFeedPage(reels: [], nextOffset: 0),
    );
    await _settle(tester);
    expect(find.text('No reels yet'), findsOneWidget);

    var fail = true;
    await _pump(
      tester,
      load: (_, _) async {
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

  testWidgets(
    'embedded top bar uses centered text tabs and compact wallet control',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pump(
        tester,
        load: (_, _) async =>
            ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1),
      );
      await _settle(tester);

      const forYou = ValueKey('reel-feed-for-you');
      const following = ValueKey('reel-feed-following');
      expect(find.byKey(forYou), findsOneWidget);
      expect(find.byKey(following), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byKey(const ValueKey('reels-top-scrim')), findsOneWidget);

      for (final key in [forYou, following]) {
        expect(
          tester.getSize(find.byKey(key)).height,
          greaterThanOrEqualTo(48),
        );
      }
      for (final key in [
        const ValueKey('reel-feed-tutorials'),
        const ValueKey('reel-feed-feedback'),
        forYou,
        following,
      ]) {
        expect(find.byKey(key), findsOneWidget);
      }
      expect(
        tester.getCenter(find.byKey(forYou)).dy,
        closeTo(tester.getCenter(find.byKey(following)).dy, 1),
      );

      final forYouSemantics = tester.widget<Semantics>(find.byKey(forYou));
      final followingSemantics = tester.widget<Semantics>(
        find.byKey(following),
      );
      expect(forYouSemantics.properties.selected, isTrue);
      expect(followingSemantics.properties.selected, isFalse);
      final forYouUnderline = find.byKey(
        const ValueKey('reel-feed-underline-for-you'),
      );
      expect(tester.getSize(forYouUnderline).height, 2);

      await tester.tap(find.byKey(following));
      await _settle(tester);
      expect(
        tester.widget<Semantics>(find.byKey(following)).properties.selected,
        isTrue,
      );
      expect(forYouUnderline, findsNothing);
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('reel-feed-underline-following')),
            )
            .height,
        2,
      );

      expect(find.byType(CoinPill), findsNothing);
    },
  );

  testWidgets('tabs scroll without coin pill at 320px', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pump(
      tester,
      load: (_, _) async =>
          ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1),
    );
    await _settle(tester);

    final tabsScroll = find.byKey(const ValueKey('reels-tabs-scroll'));
    expect(find.byType(CoinPill), findsNothing);
    expect(tabsScroll, findsOneWidget);
    expect(tester.getRect(tabsScroll).right, lessThanOrEqualTo(320));
    final forYou = find.byKey(const ValueKey('reel-feed-for-you'));
    await tester.drag(tabsScroll, const Offset(-200, 0));
    await tester.pump();
    await tester.tapAt(
      Offset(tester.getRect(forYou).right - 1, tester.getCenter(forYou).dy),
    );
  });

  testWidgets('top scrim overlays full-bleed media', (tester) async {
    await _pump(
      tester,
      load: (_, _) async =>
          ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1),
    );
    await _settle(tester);

    final feed = find.byType(PageView).first;
    expect(tester.getTopLeft(feed).dy, 0);
    final scrim = tester.getRect(find.byKey(const ValueKey('reels-top-scrim')));
    expect(scrim.height, greaterThan(64));
    expect(
      scrim.bottom,
      greaterThan(
        tester.getRect(find.byKey(const ValueKey('reel-feed-for-you'))).bottom,
      ),
    );
  });

  testWidgets('embedded home hides the upload FAB', (tester) async {
    var uploadCalls = 0;
    await _pump(
      tester,
      load: (_, _) async =>
          ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1),
      onOpenUpload: () => uploadCalls++,
    );
    await _settle(tester);

    expect(find.byTooltip('Upload reel'), findsNothing);
    expect(uploadCalls, 0);
  });

  testWidgets('unconfigured feed shows unavailable without upload', (
    tester,
  ) async {
    await _pump(
      tester,
      load: (_, _) async => throw const ApiException(
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
            load: (_, _) async => ReelFeedPage(
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
