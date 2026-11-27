import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/inbox_screen.dart';
import 'package:ghosst/services/direct_chat_service.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

class _FakeDirectChatClient implements DirectChatClient {
  _FakeDirectChatClient({this.fail = false});

  final bool fail;
  final _controller = StreamController<List<DirectThread>>.broadcast();
  String uid = 'me';
  bool failMarkRead = false;

  @override
  Future<String?> currentUid() async => uid;

  @override
  Stream<List<DirectThread>> threads() {
    if (fail) return Stream.error(Exception('offline'));
    return _controller.stream;
  }

  @override
  Stream<DirectMessageFeed> messages(String threadId) => const Stream.empty();

  @override
  Future<String?> send(String threadId, String text) async => null;

  @override
  Future<void> markRead(String threadId) async {
    if (failMarkRead) throw StateError('missing thread');
  }

  @override
  Future<bool> isBlocked(String uid) async => false;

  @override
  Future<void> block(String uid) async {}

  @override
  Future<void> unblock(String uid) async {}

  @override
  Future<bool> ensureSignedIn() async => true;

  @override
  Future<void> signOut() async {}

  void emit(List<DirectThread> threads) => _controller.add(threads);
}

DirectThread _thread({
  required String id,
  required String lastSenderId,
  required int lastMessageAt,
  Map<String, int> lastReadAt = const {},
  String lastMessage = 'hello',
}) => DirectThread(
  id: id,
  participants: ['me', id == 'me__new' ? 'new' : 'old'],
  lastMessage: lastMessage,
  lastMessageAt: lastMessageAt,
  lastSenderId: lastSenderId,
  lastReadAt: lastReadAt,
  createdAt: 1000,
  updatedAt: lastMessageAt,
);

ReelNotification _notif(
  String id,
  String type, {
  String reelId = 'r1',
  bool isRead = false,
  String? createdAt,
}) => ReelNotification(
  id: id,
  type: type,
  actor: PublicUser(
    id: '7',
    displayName: 'Juan',
    username: 'juan',
    createdAt: '',
    followerCount: 0,
    followingCount: 0,
    reelCount: 0,
  ),
  reelId: reelId,
  commentId: 'c1',
  text: 'Nice reel',
  createdAt: createdAt ?? '2026-11-27T10:00:00Z',
  isRead: isRead,
);

Future<void> _pump(
  WidgetTester tester,
  _FakeDirectChatClient client, {
  void Function(DirectThread, ChatUserSummary)? onOpenThread,
  Future<List<ChatUserSummary>> Function(List<String>)? loadUsers,
  Future<List<ChatUserSummary>> Function(String)? searchUsers,
  bool embedded = false,
  VoidCallback? onOpenWorldChat,
  ValueChanged<int>? onUnreadChanged,
  Future<List<Announcement>> Function()? loadAnnouncements,
  Future<
    ({List<ReelNotification> notifications, int unreadCount, int nextOffset})
  >
  Function()?
  loadReelNotifications,
  Future<int> Function({String? id})? markReelNotificationsRead,
  void Function(String reelId, {required bool openComments})?
  onOpenReelNotification,
  Size size = const Size(800, 600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: InboxScreen(
          key: UniqueKey(),
          client: client,
          loadUsers:
              loadUsers ??
              (ids) async => [
                for (final id in ids)
                  ChatUserSummary(
                    id: id,
                    name: id == 'new' ? 'New peer' : 'Old peer',
                  ),
              ],
          searchUsers: searchUsers,
          onOpenThread: onOpenThread,
          embedded: embedded,
          onOpenWorldChat: onOpenWorldChat,
          onUnreadChanged: onUnreadChanged,
          loadAnnouncements:
              loadAnnouncements ?? () async => const <Announcement>[],
          loadReelNotifications:
              loadReelNotifications ??
              () async => (
                notifications: const <ReelNotification>[],
                unreadCount: 0,
                nextOffset: 0,
              ),
          markReelNotificationsRead:
              markReelNotificationsRead ?? ({id}) async => 0,
          onOpenReelNotification: onOpenReelNotification,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('inbox uses TikTok chrome with circles and badges', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    int? unread;
    await _pump(
      tester,
      client,
      onUnreadChanged: (count) => unread = count,
      loadUsers: (ids) async => [
        for (final id in ids)
          ChatUserSummary(id: id, name: id == 'old' ? 'Old peer' : 'New peer'),
      ],
      loadAnnouncements: () async => [
        const Announcement(
          id: 'a1',
          title: 'New drop',
          body: 'Fresh keys are live.',
          createdAt: '2026-11-26T10:00:00.000Z',
        ),
      ],
    );
    client.emit([
      _thread(
        id: 'me__old',
        lastSenderId: 'old',
        lastMessageAt: 2000,
        lastReadAt: {'me': 1000},
        lastMessage: 'hello',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('inbox-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-circles')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-notifications')), findsNothing);
    expect(find.byKey(const ValueKey('inbox-world')), findsOneWidget);
    expect(find.byKey(const ValueKey('thread-me__old')), findsOneWidget);
    expect(unread, 1);

    await tester.tap(find.byKey(const ValueKey('inbox-tab-activity')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inbox-notifications')), findsOneWidget);
  });

  testWidgets('inbox shows all announcements as notifications', (tester) async {
    final client = _FakeDirectChatClient();
    await _pump(
      tester,
      client,
      embedded: true,
      loadAnnouncements: () async => [
        const Announcement(
          id: 'a1',
          title: 'New drop',
          body: 'Fresh keys are live in the shop.',
          createdAt: '2026-11-26T10:00:00.000Z',
        ),
        const Announcement(
          id: 'a2',
          title: 'Double coins',
          body: 'Weekend promo is live.',
          createdAt: '2026-11-25T10:00:00.000Z',
        ),
      ],
    );
    client.emit(const []);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inbox-tab-activity')));
    await tester.pumpAndSettle();

    expect(find.text('New drop'), findsOneWidget);
    expect(find.text('Fresh keys are live in the shop.'), findsOneWidget);
    expect(find.text('Double coins'), findsOneWidget);
    expect(find.text('Weekend promo is live.'), findsOneWidget);
    await tester.tap(find.text('New drop'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh keys are live in the shop.'), findsWidgets);
  });

  testWidgets('sorts newest first and marks only peer messages unread', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    final loaded = <String>[];
    final unreadTotals = <int>[];
    await _pump(
      tester,
      client,
      onUnreadChanged: unreadTotals.add,
      loadUsers: (ids) async {
        loaded.addAll(ids);
        return [
          for (final id in ids)
            ChatUserSummary(
              id: id,
              name: id == 'new' ? 'New peer' : 'Old peer',
            ),
        ];
      },
    );
    client.emit([
      _thread(
        id: 'me__old',
        lastSenderId: 'me',
        lastMessageAt: 1000,
        lastMessage: 'My old message',
      ),
      _thread(
        id: 'me__new',
        lastSenderId: 'new',
        lastMessageAt: 2000,
        lastReadAt: {'me': 1500},
        lastMessage: 'New message',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('thread-me__new')), findsOneWidget);
    expect(find.byKey(const ValueKey('thread-me__old')), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-me__new')), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-me__old')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('thread-me__new'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('thread-me__old'))).dy,
      ),
    );
    expect(loaded, containsAll(['new', 'old']));
    expect(unreadTotals, contains(1));
  });

  testWidgets('embedded inbox pins World chat above private threads', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    var worldChatOpens = 0;
    await _pump(
      tester,
      client,
      embedded: true,
      onOpenWorldChat: () => worldChatOpens++,
    );
    client.emit([
      _thread(
        id: 'me__new',
        lastSenderId: 'new',
        lastMessageAt: 2000,
        lastReadAt: {'me': 1500},
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('World chat'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(
      tester.getTopLeft(find.text('World chat')).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('thread-me__new'))).dy,
      ),
    );
    await tester.tap(find.text('World chat'));
    expect(worldChatOpens, 1);
  });

  testWidgets('shows an empty state and retries a failed stream', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    await _pump(tester, client);
    client.emit([]);
    await tester.pumpAndSettle();
    expect(find.text('No private messages yet'), findsOneWidget);

    final failing = _FakeDirectChatClient(fail: true);
    await _pump(tester, failing);
    await tester.pumpAndSettle();
    expect(find.text('Could not load messages'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('new message search opens the selected thread', (tester) async {
    final client = _FakeDirectChatClient()..failMarkRead = true;
    DirectThread? opened;
    await _pump(
      tester,
      client,
      searchUsers: (_) async => [
        const ChatUserSummary(id: 'new', name: 'New peer'),
      ],
      onOpenThread: (thread, peer) => opened = thread,
    );

    await tester.tap(find.byTooltip('New message'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'new');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Search'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('New peer'));
    await tester.tap(find.text('New peer'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(opened?.id, 'me__new');
  });

  testWidgets('activity tab lists notifications with unread dots and badge', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    await _pump(
      tester,
      client,
      loadReelNotifications: () async => (
        notifications: [
          _notif('n1', 'comment'),
          _notif('n2', 'like', reelId: 'r2', isRead: true),
        ],
        unreadCount: 1,
        nextOffset: 2,
      ),
    );
    client.emit(const []);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('inbox-tab-activity')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('inbox-activity-badge')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-notification-n1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-notification-n2')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inbox-notification-unread-n1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inbox-notification-unread-n2')),
      findsNothing,
    );
  });

  testWidgets('mark all read clears unread state', (tester) async {
    final client = _FakeDirectChatClient();
    String? markedId;
    var calls = 0;
    await _pump(
      tester,
      client,
      loadReelNotifications: () async => (
        notifications: [_notif('n1', 'comment')],
        unreadCount: 1,
        nextOffset: 1,
      ),
      markReelNotificationsRead: ({id}) async {
        markedId = id;
        calls++;
        return 0;
      },
    );
    client.emit(const []);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inbox-tab-activity')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('inbox-notifications-read-all')),
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(markedId, isNull);
    expect(find.byKey(const ValueKey('inbox-activity-badge')), findsNothing);
    expect(
      find.byKey(const ValueKey('inbox-notification-unread-n1')),
      findsNothing,
    );
  });

  testWidgets('tapping a comment notification routes to reel comments', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    String? reelId;
    bool? routedComments;
    await _pump(
      tester,
      client,
      loadReelNotifications: () async => (
        notifications: [
          _notif('n1', 'comment'),
          _notif('n2', 'like', reelId: 'r2', isRead: true),
        ],
        unreadCount: 1,
        nextOffset: 2,
      ),
      onOpenReelNotification: (id, {required bool openComments}) {
        reelId = id;
        routedComments = openComments;
      },
    );
    client.emit(const []);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inbox-tab-activity')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('inbox-notification-n1')));
    expect(reelId, 'r1');
    expect(routedComments, isTrue);
    await tester.tap(find.byKey(const ValueKey('inbox-notification-n2')));
    expect(reelId, 'r2');
    expect(routedComments, isFalse);
  });

  testWidgets('activity load failure shows retry without breaking messages', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    var fail = true;
    await _pump(
      tester,
      client,
      loadReelNotifications: () async {
        if (fail) throw StateError('offline');
        return (
          notifications: [_notif('n1', 'comment')],
          unreadCount: 1,
          nextOffset: 1,
        );
      },
    );
    client.emit([
      _thread(
        id: 'me__old',
        lastSenderId: 'old',
        lastMessageAt: 2000,
        lastMessage: 'hello',
      ),
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inbox-tab-activity')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('inbox-notifications-retry')),
      findsOneWidget,
    );
    fail = false;
    await tester.tap(find.byKey(const ValueKey('inbox-notifications-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inbox-notification-n1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('inbox-tab-messages')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('thread-me__old')), findsOneWidget);
  });

  testWidgets('activity reloads when the tab is entered again', (tester) async {
    final client = _FakeDirectChatClient();
    var rows = <ReelNotification>[_notif('n1', 'comment')];
    await _pump(
      tester,
      client,
      loadReelNotifications: () async => (
        notifications: rows,
        unreadCount: rows.length,
        nextOffset: rows.length,
      ),
    );
    client.emit(const []);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('inbox-tab-activity')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inbox-notification-n1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-notification-n2')), findsNothing);

    rows = [
      _notif('n1', 'comment'),
      _notif('n2', 'like', reelId: 'r2', isRead: true),
    ];
    await tester.tap(find.byKey(const ValueKey('inbox-tab-messages')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('inbox-tab-activity')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inbox-notification-n2')), findsOneWidget);
  });

  testWidgets('activity rows show when the action happened', (tester) async {
    final client = _FakeDirectChatClient();
    await _pump(
      tester,
      client,
      loadReelNotifications: () async => (
        notifications: [
          _notif(
            'n1',
            'comment',
            createdAt: DateTime.now()
                .subtract(const Duration(hours: 2))
                .toIso8601String(),
          ),
        ],
        unreadCount: 1,
        nextOffset: 1,
      ),
    );
    client.emit(const []);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inbox-tab-activity')));
    await tester.pumpAndSettle();

    expect(find.text('2h'), findsOneWidget);
  });

  testWidgets('opening a notification does not wait for read receipt', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    final never = Completer<int>();
    String? routed;
    await _pump(
      tester,
      client,
      loadReelNotifications: () async => (
        notifications: [_notif('n1', 'comment')],
        unreadCount: 1,
        nextOffset: 1,
      ),
      markReelNotificationsRead: ({id}) => never.future,
      onOpenReelNotification: (id, {required bool openComments}) => routed = id,
    );
    client.emit(const []);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inbox-tab-activity')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('inbox-notification-n1')));
    await tester.pump();
    expect(routed, 'r1');
  });

  testWidgets('circle shelf labels do not collide on a narrow screen', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    DirectThread thread(String peer) => DirectThread(
      id: 'me__$peer',
      participants: ['me', peer],
      lastMessage: 'hi',
      lastMessageAt: 2000,
      lastSenderId: peer,
      lastReadAt: const {},
      createdAt: 1000,
      updatedAt: 2000,
    );
    await _pump(
      tester,
      client,
      size: const Size(320, 640),
      loadUsers: (ids) async => [
        for (final id in ids)
          ChatUserSummary(
            id: id,
            name: id == 'sophie' ? 'Sophie Sophie G.' : 'Sylvie',
          ),
      ],
    );
    client.emit([thread('sophie'), thread('sylvie')]);
    await tester.pumpAndSettle();

    final shelf = find.byKey(const ValueKey('inbox-circles'));
    final world = tester.getRect(
      find.descendant(of: shelf, matching: find.text('World chat')),
    );
    final sophie = tester.getRect(
      find.descendant(of: shelf, matching: find.text('Sophie Sophie G.')),
    );
    expect(
      world.right,
      lessThan(sophie.left),
      reason: 'top circles must not run their labels together',
    );
  });

  testWidgets('circle shelf uses the available width', (tester) async {
    final client = _FakeDirectChatClient();
    await _pump(tester, client, size: const Size(320, 640));
    client.emit(const []);
    await tester.pumpAndSettle();
    final narrow = tester
        .getRect(find.byKey(const ValueKey('inbox-world')))
        .width;

    await _pump(tester, client, size: const Size(800, 600));
    client.emit(const []);
    await tester.pumpAndSettle();
    final wide = tester
        .getRect(find.byKey(const ValueKey('inbox-world')))
        .width;

    expect(wide, greaterThan(narrow + 40));
  });

  testWidgets('announcements and reel activity share the Activity tab', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    await _pump(
      tester,
      client,
      loadAnnouncements: () async => [
        const Announcement(
          id: 'a1',
          title: 'New drop',
          body: 'Fresh keys are live.',
          createdAt: '2026-11-26T10:00:00.000Z',
        ),
      ],
      loadReelNotifications: () async => (
        notifications: [_notif('n1', 'like')],
        unreadCount: 1,
        nextOffset: 1,
      ),
    );
    client.emit(const []);
    await tester.pumpAndSettle();

    expect(find.text('New drop'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('inbox-tab-activity')));
    await tester.pumpAndSettle();
    expect(find.text('New drop'), findsOneWidget);
    expect(find.byKey(const ValueKey('inbox-notification-n1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('inbox-tab-messages')));
    await tester.pumpAndSettle();
    expect(find.text('New drop'), findsNothing);
  });
}
