import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/direct_chat_screen.dart';
import 'package:ghosst/services/direct_chat_service.dart';
import 'package:ghosst/social_shell.dart';
import 'package:ghosst/theme.dart';

class _FakeDirectChatClient implements DirectChatClient {
  final _controller = StreamController<DirectMessageFeed>();
  final sent = <String>[];
  final markedRead = <String>[];
  final blocked = <String>[];
  bool failMarkRead = false;
  String? sendError;
  bool isBlockedResult = false;
  bool sessionReady = true;
  bool failMessages = false;
  String messagesError = 'permission-denied';
  int signInCalls = 0;
  int messagesCalls = 0;

  @override
  Future<String?> currentUid() async => sessionReady ? 'me' : null;

  @override
  Stream<List<DirectThread>> threads() => const Stream.empty();

  @override
  Stream<DirectMessageFeed> messages(String threadId) async* {
    messagesCalls++;
    if (failMessages) {
      yield* Stream<DirectMessageFeed>.error(StateError(messagesError));
      return;
    }
    yield* _controller.stream;
  }

  @override
  Future<String?> send(String threadId, String text) async {
    sent.add(text);
    return sendError;
  }

  @override
  Future<void> markRead(String threadId) async {
    markedRead.add(threadId);
    if (failMarkRead) throw StateError('missing thread');
  }

  @override
  Future<bool> isBlocked(String uid) async => isBlockedResult;

  @override
  Future<void> block(String uid) async {
    blocked.add(uid);
  }

  @override
  Future<void> unblock(String uid) async {}

  @override
  Future<bool> ensureSignedIn() async {
    signInCalls++;
    sessionReady = true;
    return true;
  }

  @override
  Future<void> signOut() async {}

  void emit(List<DirectMessage> messages, {bool pending = false}) => _controller
      .add(DirectMessageFeed(messages: messages, hasPendingWrites: pending));
}

DirectMessage _message(String id, String senderId, String text, int ts) =>
    DirectMessage(id: id, senderId: senderId, text: text, tsMillis: ts);

Future<void> _pump(
  WidgetTester tester,
  _FakeDirectChatClient client, {
  ValueChanged<String>? onOpenProfile,
  Future<void> Function({
    required String targetType,
    required String targetId,
    required String reason,
    String details,
    String? snapshot,
    String? threadId,
  })?
  onReport,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: DirectChatScreen(
        peerId: 'peer',
        peerName: 'Peer name',
        client: client,
        onReport: onReport,
        onOpenProfile: onOpenProfile,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('DM boot signs in before reading the current uid', (tester) async {
    final client = _FakeDirectChatClient()..sessionReady = false;
    await _pump(tester, client);
    await tester.pump();

    expect(find.text('Could not load messages'), findsNothing);
    expect(client.signInCalls, 1);
    client.emit(const []);
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('new thread shows an empty conversation and can send', (
    tester,
  ) async {
    final client = _FakeDirectChatClient()..failMessages = true;
    await _pump(tester, client);
    await tester.pumpAndSettle();

    expect(find.text('Could not load messages'), findsNothing);
    expect(find.text('No messages yet'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    client.failMessages = false;
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(client.sent, ['hello']);
    expect(client.messagesCalls, greaterThanOrEqualTo(2));
    expect(find.text('Could not load messages'), findsNothing);
  });

  testWidgets('non-permission stream errors keep the reason visible', (
    tester,
  ) async {
    final client = _FakeDirectChatClient()
      ..failMessages = true
      ..messagesError = 'network down';
    await _pump(tester, client);
    await tester.pumpAndSettle();

    expect(find.text('Could not load messages'), findsOneWidget);
    expect(find.textContaining('network down'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('DM route uses a white social app bar and 48dp actions', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    await _pump(tester, client);
    client.emit([_message('m1', 'peer', 'Hello', 1000)]);
    await tester.pumpAndSettle();

    expect(find.text('Peer name'), findsOneWidget);
    expect(find.byType(SocialAppBar), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.black);
    expect(appBar.foregroundColor, AppColors.text);
    final actions = <String, Finder>{
      'Send message': find.widgetWithIcon(IconButton, Icons.send_rounded),
      'More actions': find.byType(PopupMenuButton<String>),
      'Report message': find.widgetWithIcon(IconButton, Icons.flag_outlined),
    };
    for (final entry in actions.entries) {
      expect(
        tester.getSize(entry.value).height,
        greaterThanOrEqualTo(kTouchMin),
        reason: entry.key,
      );
    }
  });

  testWidgets('peer header opens the public profile', (tester) async {
    String? opened;
    final client = _FakeDirectChatClient();
    await _pump(tester, client, onOpenProfile: (id) => opened = id);
    client.emit([]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Peer name'));
    expect(opened, 'peer');
  });

  testWidgets('renders oldest first and aligns own messages right', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    await _pump(tester, client);
    client.emit([
      _message('m2', 'peer', 'Newer', 2000),
      _message('m1', 'me', 'Mine', 1000),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Newer'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Mine')).dy,
      lessThan(tester.getTopLeft(find.text('Newer')).dy),
    );
    final align = tester.widget<Align>(
      find.ancestor(of: find.text('Mine'), matching: find.byType(Align)).first,
    );
    expect(align.alignment, Alignment.centerRight);
    expect(client.markedRead, contains('me__peer'));
  });

  testWidgets('a missing thread read marker does not block rendering', (
    tester,
  ) async {
    final client = _FakeDirectChatClient()..failMarkRead = true;
    await _pump(tester, client);
    client.emit([_message('m1', 'peer', 'Still visible', 1000)]);
    await tester.pumpAndSettle();

    expect(find.text('Still visible'), findsOneWidget);
    expect(find.text('Could not load messages'), findsNothing);
  });

  testWidgets('pending writes show delivery state', (tester) async {
    final client = _FakeDirectChatClient();
    await _pump(tester, client);
    client.emit([_message('m1', 'me', 'Queued', 1000)], pending: true);
    await tester.pumpAndSettle();

    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('empty input never sends and a failed send restores the draft', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    await _pump(tester, client);
    client.emit([]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Send message'));
    expect(client.sent, isEmpty);

    await tester.enterText(find.byType(TextField), 'try again');
    client.sendError = 'offline';
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(client.sent, ['try again']);
    expect(find.text('try again'), findsOneWidget);
  });

  testWidgets('block action blocks the peer after confirmation', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    await _pump(tester, client);
    client.emit([]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block user'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();

    expect(client.blocked, ['peer']);
    expect(find.text('You blocked this user.'), findsOneWidget);
  });

  testWidgets('user report is available from an empty conversation', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    String? reportedType;
    String? reportedTarget;
    await _pump(
      tester,
      client,
      onReport:
          ({
            required String targetType,
            required String targetId,
            required String reason,
            String details = '',
            String? snapshot,
            String? threadId,
          }) async {
            reportedType = targetType;
            reportedTarget = targetId;
          },
    );
    client.emit([]);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report user'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Submit report'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Submit report'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(reportedType, 'user');
    expect(reportedTarget, 'peer');
  });

  testWidgets('message report includes the reported text snapshot', (
    tester,
  ) async {
    final client = _FakeDirectChatClient();
    String? reportedId;
    String? reportedSnapshot;
    await _pump(
      tester,
      client,
      onReport:
          ({
            required String targetType,
            required String targetId,
            required String reason,
            String details = '',
            String? snapshot,
            String? threadId,
          }) async {
            reportedId = targetId;
            reportedSnapshot = snapshot;
          },
    );
    client.emit([_message('m1', 'peer', 'Report me', 1000)]);
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Report me'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).last, 'Spam content');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Submit report'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(reportedId, 'm1');
    expect(reportedSnapshot, 'Report me');
  });
}
