import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/profile_hub_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

PublicUser _user({String bio = '', String? coverUrl}) => PublicUser(
  id: '42',
  displayName: 'Jeric',
  username: 'jeric',
  createdAt: '',
  bio: bio,
  coverUrl: coverUrl,
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
  Future<String> Function(String bio)? onSaveBio,
  Future<String> Function()? onPickCover,
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
  onSaveBio: onSaveBio,
  onPickCover: onPickCover,
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
        loadReels: (_, _) async => [_reel('r1'), _reel('r2')],
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
        loadReels: (_, _) async => [_reel('r1')],
      ),
    );

    for (final label in ['Keys', 'Wallet', 'Feedback', 'Admin', 'Settings']) {
      await tester.tap(find.byKey(const ValueKey('profile-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
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
        loadReels: (_, _) async => const [],
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
        loadReels: (_, _) async => const [],
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
        loadReels: (_, _) async => const [],
      ),
    );
    expect(find.text('Jeric'), findsOneWidget);
    expect(find.text('Could not load profile'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-menu')), findsOneWidget);
  });

  testWidgets('tiktok profile chrome moves utilities behind an overflow menu', (
    tester,
  ) async {
    final calls = <String>[];
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
        loadProfile: (_) async => _user(),
        loadReels: (_, _) async => const [],
      ),
    );

    expect(find.byKey(const ValueKey('profile-tiktok-header')), findsOneWidget);
    expect(find.text('Posts'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-posts-indicator')),
      findsOneWidget,
    );
    for (final label in ['Keys', 'Wallet', 'Feedback', 'Admin']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.byIcon(Icons.settings_outlined), findsNothing);

    await tester.tap(find.byKey(const ValueKey('profile-menu')));
    await tester.pumpAndSettle();
    for (final label in ['Settings', 'Keys', 'Wallet', 'Feedback', 'Admin']) {
      expect(find.text(label), findsOneWidget);
    }
    var menuOpen = true;
    for (final entry in {
      'Settings': 'settings',
      'Keys': 'keys',
      'Wallet': 'wallet',
      'Feedback': 'feedback',
      'Admin': 'admin',
    }.entries) {
      if (!menuOpen) {
        await tester.tap(find.byKey(const ValueKey('profile-menu')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      menuOpen = false;
    }
    await tester.tap(find.byTooltip('Share app'));
    await tester.pump();
    expect(calls, ['settings', 'keys', 'wallet', 'feedback', 'admin', 'share']);
  });

  testWidgets('non-admin profile menu hides Admin', (tester) async {
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
        loadReels: (_, _) async => const [],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('profile-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Admin'), findsNothing);
    expect(find.text('Keys'), findsOneWidget);
  });

  testWidgets('own reels render as an edge-to-edge TikTok grid', (tester) async {
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
        loadReels: (_, _) async => [_reel('r1'), _reel('r2'), _reel('r3')],
      ),
    );

    expect(find.text('Your reels'), findsNothing);
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
    expect(delegate.crossAxisSpacing, 2);
    expect(delegate.mainAxisSpacing, 2);
    expect(delegate.childAspectRatio, 0.75);
    expect(find.byKey(const ValueKey('profile-reel-r1')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-reel-r2')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-reel-r3')), findsOneWidget);
  });

  testWidgets('reel failure keeps Retry on the TikTok profile', (tester) async {
    var fail = true;
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
        loadReels: (_, _) async {
          if (fail) throw Exception('offline');
          return [_reel('r9')];
        },
      ),
    );
    expect(find.text('Could not load reels'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -220));
    await tester.pump();
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('profile-reel-r9')), findsOneWidget);
  });

  testWidgets('TikTok profile fits a 320px screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
        loadReels: (_, _) async => [_reel('r1'), _reel('r2'), _reel('r3')],
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit profile shows bio and cover and saves changes', (
    tester,
  ) async {
    final saved = <String>[];
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
        loadProfile: (_) async => _user(
          bio: 'I make maps.',
          coverUrl: 'https://example.com/cover.jpg',
        ),
        loadReels: (_, _) async => const [],
        onSaveBio: (bio) async {
          saved.add(bio);
          return bio;
        },
        onPickCover: () async => 'https://example.com/new-cover.jpg',
      ),
    );

    expect(find.text('I make maps.'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-cover-band')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-bio-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-cover-pick')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('profile-bio-field')),
      'New bio here',
    );
    await tester.tap(find.byKey(const ValueKey('profile-save')));
    await tester.pumpAndSettle();
    expect(saved, ['New bio here']);
  });
}
