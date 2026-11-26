import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/profile_hub_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

PublicUser _user() => PublicUser(
  id: '42',
  displayName: 'Jeric',
  username: 'jeric',
  createdAt: '',
  followerCount: 34,
  followingCount: 12,
  reelCount: 2,
);

Reel _reel(String id) => Reel(
  id: id,
  caption: '',
  posterUrl: 'https://example.com/$id.jpg',
  images: [
    ReelImage(
      position: 1,
      url: 'https://example.com/$id.jpg',
      sha256: 'a' * 64,
      sizeBytes: 1,
      mimeType: 'image/jpeg',
    ),
  ],
  createdAt: '',
  creator: _user(),
  likeCount: 0,
  commentCount: 0,
);

Future<void> _pump(
  WidgetTester tester, {
  required ProfileHubScreen screen,
}) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: screen));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 8 && target.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -220));
    await tester.pump(const Duration(milliseconds: 250));
  }
  expect(target, findsOneWidget);
}

ProfileHubScreen _screen({
  required bool isAdmin,
  required VoidCallback onOpenKeys,
  required VoidCallback onOpenWallet,
  required VoidCallback onOpenFeedback,
  required VoidCallback onOpenAdmin,
  required VoidCallback onOpenSettings,
  required VoidCallback onOpenShare,
  ValueChanged<Reel>? onOpenReel,
  Future<PublicUser> Function(String id)? loadProfile,
  Future<List<Reel>> Function(String id, int offset)? loadReels,
}) => ProfileHubScreen(
  userId: '42',
  displayName: 'Jeric',
  isAdmin: isAdmin,
  onOpenKeys: onOpenKeys,
  onOpenWallet: onOpenWallet,
  onOpenFeedback: onOpenFeedback,
  onOpenAdmin: onOpenAdmin,
  onOpenSettings: onOpenSettings,
  onOpenShare: onOpenShare,
  onOpenReel: onOpenReel,
  loadProfile: loadProfile,
  loadReels: loadReels,
);

void main() {
  testWidgets('dashboard shows identity, stats, actions, and reel grid', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: _screen(
        isAdmin: true,
        onOpenKeys: () {},
        onOpenWallet: () {},
        onOpenFeedback: () {},
        onOpenAdmin: () {},
        onOpenSettings: () {},
        onOpenShare: () {},
        loadProfile: (_) async => _user(),
        loadReels: (_, __) async => [_reel('r1'), _reel('r2')],
      ),
    );

    expect(find.text('Jeric'), findsOneWidget);
    expect(find.text('@jeric'), findsOneWidget);
    expect(
      find.text('Official drops, updates, and community reels.'),
      findsOneWidget,
    );
    expect(find.text('12'), findsOneWidget);
    expect(find.text('34'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Keys'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Feedback'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Share app'), findsOneWidget);
    await _scrollTo(tester, find.byKey(const ValueKey('profile-reel-r1')));
    expect(find.byKey(const ValueKey('profile-reel-r1')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-reel-r2')), findsOneWidget);
    expect(find.text('Edit profile'), findsNothing);
  });

  testWidgets('dashboard actions and reel selection invoke callbacks', (
    tester,
  ) async {
    final calls = <String>[];
    Reel? opened;
    await _pump(
      tester,
      screen: _screen(
        isAdmin: true,
        onOpenKeys: () => calls.add('keys'),
        onOpenWallet: () => calls.add('wallet'),
        onOpenFeedback: () => calls.add('feedback'),
        onOpenAdmin: () => calls.add('admin'),
        onOpenSettings: () => calls.add('settings'),
        onOpenShare: () => calls.add('share'),
        onOpenReel: (reel) => opened = reel,
        loadProfile: (_) async => _user(),
        loadReels: (_, __) async => [_reel('r1')],
      ),
    );

    await tester.tap(find.text('Keys'));
    await tester.tap(find.text('Wallet'));
    await tester.tap(find.text('Feedback'));
    await tester.tap(find.text('Admin'));
    await tester.tap(find.byTooltip('Settings'));
    await tester.tap(find.byTooltip('Share app'));
    await _scrollTo(tester, find.byKey(const ValueKey('profile-reel-r1')));
    await tester.tap(find.byKey(const ValueKey('profile-reel-r1')));
    await tester.pump();

    expect(calls, ['keys', 'wallet', 'feedback', 'admin', 'settings', 'share']);
    expect(opened?.id, 'r1');
  });

  testWidgets('Admin chip is hidden for non-admins', (tester) async {
    await _pump(
      tester,
      screen: _screen(
        isAdmin: false,
        onOpenKeys: () {},
        onOpenWallet: () {},
        onOpenFeedback: () {},
        onOpenAdmin: () {},
        onOpenSettings: () {},
        onOpenShare: () {},
        loadProfile: (_) async => _user(),
        loadReels: (_, __) async => const [],
      ),
    );
    expect(find.text('Admin'), findsNothing);
  });

  testWidgets('Share invokes only the app-invite callback', (tester) async {
    final calls = <String>[];
    await _pump(
      tester,
      screen: _screen(
        isAdmin: false,
        onOpenKeys: () => calls.add('keys'),
        onOpenWallet: () => calls.add('wallet'),
        onOpenFeedback: () => calls.add('feedback'),
        onOpenAdmin: () => calls.add('admin'),
        onOpenSettings: () => calls.add('settings'),
        onOpenShare: () => calls.add('share'),
        loadProfile: (_) async => _user(),
        loadReels: (_, __) async => const [],
      ),
    );
    await tester.tap(find.byTooltip('Share app'));
    expect(calls, ['share']);
  });

  testWidgets('profile failure keeps identity and actions usable', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: _screen(
        isAdmin: false,
        onOpenKeys: () {},
        onOpenWallet: () {},
        onOpenFeedback: () {},
        onOpenAdmin: () {},
        onOpenSettings: () {},
        onOpenShare: () {},
        loadProfile: (_) async => throw Exception('offline'),
        loadReels: (_, __) async => const [],
      ),
    );
    expect(find.text('Jeric'), findsOneWidget);
    expect(find.text('Could not load profile'), findsOneWidget);
    expect(find.text('Keys'), findsOneWidget);
    expect(find.text('Wallet'), findsOneWidget);
  });
}
