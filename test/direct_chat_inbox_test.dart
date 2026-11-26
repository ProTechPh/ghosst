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

Future<void> _pump(
  WidgetTester tester,
  _FakeDirectChatClient client, {
  void Function(DirectThread, ChatUserSummary)? onOpenThread,
  Future<List<ChatUserSummary>> Function(List<String>)? loadUsers,
  Future<List<ChatUserSummary>> Function(String)? searchUsers,
  bool embedded = false,
  VoidCallback? onOpenWorldChat,
  ValueChanged<int>? onUnreadChanged,
}) async {
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
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
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

    expect(find.text('New peer'), findsOneWidget);
    expect(find.text('Old peer'), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-me__new')), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-me__old')), findsNothing);
    expect(
      tester.getTopLeft(find.text('New peer')).dy,
      lessThan(tester.getTopLeft(find.text('Old peer')).dy),
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
      lessThan(tester.getTopLeft(find.text('New peer')).dy),
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
}
