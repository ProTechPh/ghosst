import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/direct_chat_screen.dart';
import 'package:ghosst/services/direct_chat_service.dart';
import 'package:ghosst/theme.dart';

class _FakeDirectChatClient implements DirectChatClient {
  final _controller = StreamController<List<DirectMessage>>();
  final sent = <String>[];
  final markedRead = <String>[];
  final blocked = <String>[];
  String? sendError;
  bool isBlockedResult = false;

  @override
  Future<String?> currentUid() async => 'me';

  @override
  Stream<List<DirectThread>> threads() => const Stream.empty();

  @override
  Stream<List<DirectMessage>> messages(String threadId) => _controller.stream;

  @override
  Future<String?> send(String threadId, String text) async {
    sent.add(text);
    return sendError;
  }

  @override
  Future<void> markRead(String threadId) async {
    markedRead.add(threadId);
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
  Future<bool> ensureSignedIn() async => true;

  @override
  Future<void> signOut() async {}

  void emit(List<DirectMessage> messages) => _controller.add(messages);
}

DirectMessage _message(String id, String senderId, String text, int ts) =>
    DirectMessage(id: id, senderId: senderId, text: text, tsMillis: ts);

Future<void> _pump(
  WidgetTester tester,
  _FakeDirectChatClient client, {
  Future<void> Function({
    required String targetType,
    required String targetId,
    required String reason,
    String details,
    String? snapshot,
  })?
  onReport,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: DirectChatScreen(
          peerId: 'peer',
          peerName: 'Peer name',
          client: client,
          onReport: onReport,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
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
