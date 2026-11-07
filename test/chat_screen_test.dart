import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/chat_screen.dart';
import 'package:ghosst/services/chat_service.dart';
import 'package:ghosst/theme.dart';

class _FakeClient implements ChatClient {
  _FakeClient({
    this.ready = true,
    this.signedIn = true,
    this.muted = false,
  });

  @override
  final bool ready;
  final bool signedIn;
  final bool muted;
  static const myUid = 'uid-1';

  final _controller = StreamController<List<ChatMessage>>();
  final sent = <String>[];
  final sentReplyTo = <ChatMessage?>[];
  final muteCalls = <String>[];
  int subscribes = 0;
  String? sendError;
  String? muteError;

  @override
  Future<bool> ensureSignedIn() async => signedIn;

  @override
  Future<String?> currentUid() async => myUid;

  @override
  Future<bool> isMuted() async => muted;

  @override
  Future<String?> setUserMuted(String uid, bool muted) async {
    muteCalls.add('$uid:$muted');
    return muteError;
  }

  @override
  Stream<List<ChatMessage>> messages() {
    subscribes++;
    return _controller.stream;
  }

  @override
  Future<String?> send(String text, {ChatMessage? replyTo}) async {
    sent.add(text);
    sentReplyTo.add(replyTo);
    return sendError;
  }

  @override
  Future<void> signOut() async {}

  void failStream(Object error) => _controller.addError(error);
}

ChatMessage _msg({
  String? id,
  String uid = 'uid-1',
  String name = 'Jeric',
  required String text,
  bool admin = false,
  String? replyName,
  String? replyText,
}) {
  return ChatMessage(
    id: id ?? 'doc-$text',
    uid: uid,
    name: name,
    text: text,
    admin: admin,
    tsMillis: DateTime.now().millisecondsSinceEpoch,
    replyName: replyName,
    replyText: replyText,
  );
}

Future<void> _pump(
  WidgetTester tester,
  ChatClient client, {
  bool active = true,
  bool isAdmin = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: ChatScreen(client: client, active: active, isAdmin: isAdmin),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('shows the fallback when Firebase is not ready', (tester) async {
    await _pump(tester, _FakeClient(ready: false));

    expect(find.text('Chat unavailable'), findsOneWidget);
  });

  testWidgets('does not subscribe when sign-in fails', (tester) async {
    final client = _FakeClient(signedIn: false);
    await _pump(tester, client);
    await tester.pumpAndSettle();

    expect(find.text('Chat unavailable'), findsOneWidget);
    expect(client.subscribes, 0);
  });

  testWidgets('a dead message stream falls back instead of hanging',
      (tester) async {
    final client = _FakeClient();
    await _pump(tester, client);
    await tester.pumpAndSettle();

    client.failStream(Exception('permission-denied'));
    await tester.pumpAndSettle();

    expect(find.text('Chat unavailable'), findsOneWidget);
  });

  testWidgets('renders messages, the ADMIN chip, and Deleted user',
      (tester) async {
    final client = _FakeClient();
    await _pump(tester, client);
    await tester.pumpAndSettle();

    client._controller.add([
      _msg(uid: 'uid-2', text: 'Bagong stock mamaya', admin: true),
      _msg(uid: 'uid-2', name: '', text: 'Salamat boss'),
    ]);
    // Stream delivery is a microtask; the first pump renders the pre-event
    // frame, so let the setState it schedules land too.
    await tester.pumpAndSettle();

    expect(find.text('Bagong stock mamaya'), findsOneWidget);
    expect(find.text('Salamat boss'), findsOneWidget);
    expect(find.text('ADMIN'), findsOneWidget);
    expect(find.text('Deleted user'), findsOneWidget);
  });

  testWidgets('empty input never sends; typed text does', (tester) async {
    final client = _FakeClient();
    await _pump(tester, client);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(client.sent, isEmpty);

    await tester.enterText(find.byType(TextField), '  hello  ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(client.sent, ['  hello  ']);
  });

  testWidgets('a failed send surfaces the reason in a SnackBar',
      (tester) async {
    final client = _FakeClient()..sendError = 'Could not send — try again.';
    await _pump(tester, client);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('Could not send — try again.'), findsOneWidget);
  });

  testWidgets('an inactive tab subscribes only once selected', (tester) async {
    final client = _FakeClient();
    await _pump(tester, client, active: false);
    await tester.pumpAndSettle();
    expect(client.subscribes, 0);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: ChatScreen(client: client)),
    ));
    await tester.pumpAndSettle();

    expect(client.subscribes, 1);
  });

  testWidgets('swipe right opens the reply preview; X cancels it',
      (tester) async {
    final client = _FakeClient();
    await _pump(tester, client);
    await tester.pumpAndSettle();

    client._controller.add([_msg(uid: 'uid-2', text: 'Hello')]);
    await tester.pumpAndSettle();

    await tester.drag(find.text('Hello'), const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(find.text('Reply to Jeric'), findsOneWidget);
    // Quoted text appears in the preview (in addition to the bubble).
    expect(find.text('Hello'), findsWidgets);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Reply to Jeric'), findsNothing);
  });

  testWidgets('send passes the reply target and clears the preview',
      (tester) async {
    final client = _FakeClient();
    await _pump(tester, client);
    await tester.pumpAndSettle();

    client._controller.add([_msg(uid: 'uid-2', text: 'Hello')]);
    await tester.pumpAndSettle();

    await tester.drag(find.text('Hello'), const Offset(600, 0));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hi!');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(client.sent, ['Hi!']);
    expect(client.sentReplyTo.single?.name, 'Jeric');
    expect(client.sentReplyTo.single?.text, 'Hello');
    expect(find.text('Reply to Jeric'), findsNothing);
  });

  testWidgets('shows loading until the first snapshot, then the empty state',
      (tester) async {
    final client = _FakeClient();
    await _pump(tester, client);
    await tester.pump();

    // Bago ang unang snapshot: loading — hindi ang empty state.
    expect(find.text('Loading chat…'), findsOneWidget);
    expect(find.text('No messages yet. Be the first.'), findsNothing);

    client._controller.add([]);
    await tester.pumpAndSettle();

    expect(find.text('No messages yet. Be the first.'), findsOneWidget);
  });

  testWidgets('admin long-press opens the mute dialog', (tester) async {
    final client = _FakeClient();
    await _pump(tester, client, isAdmin: true);
    await tester.pumpAndSettle();

    client._controller.add([_msg(uid: 'uid-2', text: 'Hello')]);
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Hello'));
    await tester.pumpAndSettle();

    expect(find.text('Mute Jeric in world chat?'), findsOneWidget);

    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();

    expect(client.muteCalls, ['uid-2:true']);
    expect(find.text('User muted.'), findsOneWidget);
  });

  testWidgets('non-admin long-press shows no dialog', (tester) async {
    final client = _FakeClient();
    await _pump(tester, client);
    await tester.pumpAndSettle();

    client._controller.add([_msg(uid: 'uid-2', text: 'Hello')]);
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Hello'));
    await tester.pumpAndSettle();

    expect(find.text('Chat moderation'), findsNothing);
    expect(client.muteCalls, isEmpty);
  });

  testWidgets('admin long-press on own message shows no dialog',
      (tester) async {
    final client = _FakeClient();
    await _pump(tester, client, isAdmin: true);
    await tester.pumpAndSettle();

    client._controller.add([_msg(text: 'Mine')]);
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Mine'));
    await tester.pumpAndSettle();

    expect(find.text('Chat moderation'), findsNothing);
    expect(client.muteCalls, isEmpty);
  });

  testWidgets('a muted user sees the muted bar instead of the composer',
      (tester) async {
    final client = _FakeClient(muted: true);
    await _pump(tester, client);
    await tester.pumpAndSettle();

    expect(find.text('You are muted in this chat.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('renders the reply quote inside the bubble', (tester) async {
    final client = _FakeClient();
    await _pump(tester, client);
    await tester.pumpAndSettle();

    client._controller.add([
      _msg(
        uid: 'uid-2',
        text: 'Sagot ko',
        replyName: 'Abbie',
        replyText: 'Tanong niya',
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Abbie'), findsOneWidget);
    expect(find.text('Tanong niya'), findsOneWidget);
    expect(find.text('Sagot ko'), findsOneWidget);
  });
}
