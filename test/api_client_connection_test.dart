import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/api_client.dart';

void main() {
  group('ApiClient.connectApiSocket', () {
    test('tries a later address when the first connection fails', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadAddress = InternetAddress('192.0.2.1');
      final attempts = <InternetAddress>[];

      try {
        final task = await ApiClient.connectApiSocket(
          Uri.parse('http://example.test:${server.port}'),
          resolve: (_) async => [deadAddress, server.address],
          startConnect: (address, port) async {
            attempts.add(address);
            if (address == deadAddress) {
              throw const SocketException('connection refused');
            }
            return Socket.startConnect(address, port);
          },
        );

        final socket = await task.socket.timeout(const Duration(seconds: 2));
        expect(socket.address, server.address);
        expect(attempts, [deadAddress, server.address]);
        socket.close();
      } finally {
        server.close();
      }
    });

    test('cancels an in-flight TCP attempt', () async {
      final started = Completer<void>();
      final pendingSocket = Completer<Socket>();
      var connectorCancelled = false;

      final task = await ApiClient.connectApiSocket(
        Uri.parse('http://example.test:80'),
        resolve: (_) async => [InternetAddress('192.0.2.1')],
        startConnect: (_, _) async {
          started.complete();
          return ConnectionTask.fromSocket(pendingSocket.future, () {
            connectorCancelled = true;
            if (!pendingSocket.isCompleted) {
              pendingSocket.completeError(
                const SocketException('connection cancelled'),
              );
            }
          });
        },
      );
      final outcome = expectLater(
        task.socket,
        throwsA(isA<SocketException>()),
      );

      await started.future;
      task.cancel();
      await outcome;

      expect(connectorCancelled, isTrue);
    });

    test('fails clearly when DNS returns no addresses', () async {
      final task = await ApiClient.connectApiSocket(
        Uri.parse('http://example.test:80'),
        resolve: (_) async => const [],
      );

      await expectLater(
        task.socket,
        throwsA(
          isA<SocketException>().having(
            (error) => error.message,
            'message',
            contains('No address for example.test'),
          ),
        ),
      );
    });
  });
}
