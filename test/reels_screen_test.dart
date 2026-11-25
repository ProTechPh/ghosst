import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/api_exception.dart';
import 'package:ghosst/screens/direct_chat_screen.dart' show ReportContent;
import 'package:ghosst/screens/reels_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

class _FakePlayback implements ReelPlayback {
  bool playing = false;
  bool muted = false;
  bool disposed = false;
  bool fail = false;

  @override
  Future<void> initialize() async {
    if (fail) throw StateError('video unavailable');
  }

  @override
  Future<void> play() async => playing = true;

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> setMuted(bool value) async => muted = value;

  @override
  bool get isPlaying => playing;

  @override
  void dispose() => disposed = true;

  @override
  Widget view() => const ColoredBox(color: Colors.black);
}

Reel _reel(String id, String name) => Reel(
  id: id,
  caption: 'Caption $id',
  posterUrl: 'https://example.com/$id-1.jpg',
  images: [
    ReelImage(
      position: 1,
      url: 'https://example.com/$id-1.jpg',
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
);

Future<void> _pump(
  WidgetTester tester, {
  required Future<ReelFeedPage> Function(String, int) load,
  ReelPlaybackFactory? playbackFactory,
  Future<void> Function(String)? onLike,
  Future<void> Function(String)? onUnlike,
  ValueChanged<String>? onOpenProfile,
  ReportContent? onReport,
  VoidCallback? onOpenUpload,
  Future<void> Function(String)? onDeleteReel,
  bool active = true,
}) async {
  final key = UniqueKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ReelsScreen(
          key: key,
          load: load,
          playbackFactory: playbackFactory,
          onLike: onLike,
          onUnlike: onUnlike,
          onOpenProfile: onOpenProfile,
          onReport: onReport,
          onOpenUpload: onOpenUpload,
          onDeleteReel: onDeleteReel,
          active: active,
          loadComments: (_, __) async => [],
          submitComment: (_, __) async {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('inactive tab loads on first activation and pauses offscreen', (
    tester,
  ) async {
    final player = _FakePlayback();
    final key = GlobalKey();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ReelsScreen(
            key: key,
            active: false,
            load: (_, _) async {
              calls++;
              return ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1);
            },
            playbackFactory: (_) => player,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(calls, 0);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ReelsScreen(
            key: key,
            active: true,
            load: (_, _) async {
              calls++;
              return ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1);
            },
            playbackFactory: (_) => player,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, 1);
    expect(player.playing, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ReelsScreen(
            key: key,
            active: false,
            load: (_, _) async => const ReelFeedPage(reels: [], nextOffset: 0),
            playbackFactory: (_) => player,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(player.playing, isFalse);
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
      playbackFactory: (_) => _FakePlayback(),
    );
    await tester.tap(find.text('Following'));
    await tester.pump();
    second.complete(
      ReelFeedPage(reels: [_reel('following', 'Followed')], nextOffset: 1),
    );
    await tester.pumpAndSettle();
    expect(find.text('Caption following'), findsOneWidget);
    first.complete(
      ReelFeedPage(reels: [_reel('stale', 'Stale')], nextOffset: 1),
    );
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Caption following'), findsOneWidget);
    expect(find.text('Caption stale'), findsNothing);
  });

  testWidgets('owner can delete a reel and its player is disposed', (
    tester,
  ) async {
    final player = _FakePlayback();
    final owned = Reel(
      id: 'mine',
      caption: 'Mine',
      posterUrl: 'https://example.com/mine-1.jpg',
      images: [
        ReelImage(
          position: 1,
          url: 'https://example.com/mine-1.jpg',
          sha256: 'a' * 64,
          sizeBytes: 1,
          mimeType: 'image/jpeg',
        ),
      ],
      createdAt: '',
      creator: _reel('mine', 'Me').creator,
      likeCount: 0,
      commentCount: 0,
      isMine: true,
    );
    String? deleted;
    await _pump(
      tester,
      load: (_, _) async {
        if (deleted != null) {
          return const ReelFeedPage(reels: [], nextOffset: 0);
        }
        return ReelFeedPage(reels: [owned], nextOffset: 1);
      },
      playbackFactory: (_) => player,
      onDeleteReel: (id) async => deleted = id,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reel-delete-mine')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, 'mine');
    expect(player.disposed, isTrue);
    expect(find.text('No reels yet'), findsOneWidget);
  });

  testWidgets('segments, active playback, mute, pause, and page changes', (
    tester,
  ) async {
    final players = <_FakePlayback>[];
    await _pump(
      tester,
      load: (_, __) async => ReelFeedPage(
        reels: [_reel('r1', 'One'), _reel('r2', 'Two')],
        nextOffset: 2,
      ),
      playbackFactory: (_) {
        final player = _FakePlayback();
        players.add(player);
        return player;
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('For You'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(players.first.muted, isTrue);
    expect(players.first.playing, isTrue);

    await tester.tap(find.byKey(const ValueKey('reel-video-r1')));
    await tester.pump();
    expect(players.first.playing, isFalse);
    await tester.tap(find.byKey(const ValueKey('reel-video-r1')));
    await tester.pump();
    expect(players.first.playing, isTrue);

    await tester.tap(find.byKey(const ValueKey('reel-sound')));
    await tester.pump();
    expect(players.first.muted, isFalse);

    await tester.drag(find.byType(PageView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(players.first.playing, isFalse);
    expect(players.last.playing, isTrue);
  });

  testWidgets('like, comments, profile, and report actions work', (
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
      playbackFactory: (_) => _FakePlayback(),
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
    await tester.pumpAndSettle();

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('reel-profile-One')));
    await tester.tap(find.byKey(const ValueKey('reel-report-r1')));
    await tester.pumpAndSettle();
    expect(find.text('Report reel'), findsOneWidget);
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();
    expect(profile, 'One');
    expect(report, 'reel:r1');
  });

  testWidgets('empty and error states support Retry', (tester) async {
    await _pump(
      tester,
      load: (_, __) async => const ReelFeedPage(reels: [], nextOffset: 0),
      playbackFactory: (_) => _FakePlayback(),
    );
    await tester.pumpAndSettle();
    expect(find.text('No reels yet'), findsOneWidget);

    var fail = true;
    await _pump(
      tester,
      load: (_, __) async {
        if (fail) throw Exception('offline');
        return ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1);
      },
      playbackFactory: (_) => _FakePlayback(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load reels'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Caption r1'), findsOneWidget);
  });

  testWidgets('video failure and upload entry are visible', (tester) async {
    final player = _FakePlayback()..fail = true;
    var openedUpload = false;
    await _pump(
      tester,
      load: (_, __) async =>
          ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1),
      playbackFactory: (_) => player,
      onOpenUpload: () => openedUpload = true,
    );
    await tester.pumpAndSettle();
    expect(find.text('Video unavailable'), findsOneWidget);
    await tester.tap(find.byTooltip('Upload reel'));
    expect(openedUpload, isTrue);
  });

  testWidgets('unconfigured feed pauses playback and shows upload', (
    tester,
  ) async {
    final player = _FakePlayback();
    await _pump(
      tester,
      load: (_, __) async => throw const ApiException(
        kind: ApiErrorKind.server,
        message: 'not configured',
        code: 'reels_not_configured',
      ),
      playbackFactory: (_) => player,
      onOpenUpload: () {},
    );
    await tester.pumpAndSettle();
    expect(find.text('Reels unavailable'), findsOneWidget);
    expect(player.playing, isFalse);
  });

  testWidgets('distant playback is paused and disposed', (tester) async {
    final players = <_FakePlayback>[];
    await _pump(
      tester,
      load: (_, _) async => ReelFeedPage(
        reels: [_reel('r1', 'One'), _reel('r2', 'Two'), _reel('r3', 'Three')],
        nextOffset: 3,
      ),
      playbackFactory: (_) {
        final player = _FakePlayback();
        players.add(player);
        return player;
      },
    );
    await tester.pumpAndSettle();
    final pageView = find.byType(PageView);
    await tester.drag(pageView, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(players.first.disposed, isFalse);
    await tester.drag(pageView, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(players.first.disposed, isTrue);
    expect(players.first.playing, isFalse);
  });

  testWidgets('initial reel from a later page is prepended and selected', (
    tester,
  ) async {
    final players = <_FakePlayback>[];
    final selected = _reel('selected', 'Creator');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ReelsScreen(
            embedded: false,
            initialReelId: selected.id,
            playbackFactory: (_) {
              final player = _FakePlayback();
              players.add(player);
              return player;
            },
            load: (_, _) async => ReelFeedPage(
              reels: [_reel('r1', 'Other'), selected],
              nextOffset: 2,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Caption selected'), findsOneWidget);
    expect(find.text('Caption r1'), findsNothing);
    expect(players.last.playing, isTrue);
  });

  testWidgets('playback is disposed with the feed', (tester) async {
    final player = _FakePlayback();
    await _pump(
      tester,
      load: (_, __) async =>
          ReelFeedPage(reels: [_reel('r1', 'One')], nextOffset: 1),
      playbackFactory: (_) => player,
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(player.disposed, isTrue);
  });
}
