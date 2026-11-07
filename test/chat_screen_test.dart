import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/chat_screen.dart';
import 'package:ghosst/services/chat_service.dart';
import 'package:ghosst/theme.dart';

class _FakeClient implements ChatClient {
  _FakeClient({this.ready = true});

  @override
  final bool ready;

  final _controller = StreamController<List<ChatMessage>>();
  final sent = <String>[];

  @override
  Stream<List<ChatMessage>> messages() => _controller.stream;

  @override
  Future<String?> send(String text) async {
    sent.add(text);
    return null;
  }

  @override
  Future<void> signOut() async {}
}

ChatMessage _msg({
  String uid = 'uid-1',
  String name = 'Jeric',
  required String text,
  bool admin = false,
}) {
  return ChatMessage(
    uid: uid,
    name: name,
    text: text,
    admin: admin,
    tsMillis: DateTime.now().millisecondsSinceEpoch,
  );
}

Future<void> _pump(WidgetTester tester, ChatClient client) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: ChatScreen(client: client)),
  ));
  await tester.pump();
}

void main() {
  testWidgets('shows the fallback when Firebase is not ready', (tester) async {
    await _pump(tester, _FakeClient(ready: false));

    expect(find.text('Chat unavailable'), findsOneWidget);
  });

  testWidgets('renders messages, the ADMIN chip, and Deleted user',
      (tester) async {
    final client = _FakeClient();
    await _pump(tester, client);

    client._controller.add([
      _msg(text: 'Bagong stock mamaya', admin: true),
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

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();
    expect(client.sent, isEmpty);

    await tester.enterText(find.byType(TextField), '  hello  ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(client.sent, ['  hello  ']);
  });
}
