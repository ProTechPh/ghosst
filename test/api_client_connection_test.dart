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

    test(
      'uses DoH after system DNS fails and keeps the API host for SNI',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        String? tlsHost;
        var dohLookups = 0;

        try {
          final task = await ApiClient.connectApiSocket(
            Uri.parse('https://example.test:${server.port}'),
            resolve: (_) async =>
                throw const SocketException('DNS unavailable'),
            resolveDoh: (_) async {
              dohLookups++;
              return [server.address];
            },
            secure: (socket, host) async {
              tlsHost = host;
              socket.close();
              return _FakeSecureSocket();
            },
          );

          await task.socket.timeout(const Duration(seconds: 2));

          expect(dohLookups, 1);
          expect(tlsHost, 'example.test');
        } finally {
          server.close();
        }
      },
    );

    test('uses DoH when a system DNS answer fails the TLS handshake', () async {
      final systemServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final dohServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      var handshakes = 0;
      var dohLookups = 0;

      try {
        final task = await ApiClient.connectApiSocket(
          Uri.parse('https://example.test:${systemServer.port}'),
          resolve: (_) async => [systemServer.address],
          resolveDoh: (_) async {
            dohLookups++;
            return [dohServer.address];
          },
          startConnect: (address, port) => Socket.startConnect(
            address,
            address == systemServer.address ? systemServer.port : port,
          ),
          secure: (socket, _) async {
            handshakes++;
            socket.close();
            if (handshakes == 1) {
              throw const HandshakeException('certificate does not match');
            }
            return _FakeSecureSocket();
          },
        );

        await task.socket.timeout(const Duration(seconds: 2));

        expect(dohLookups, 1);
        expect(handshakes, 2);
      } finally {
        systemServer.close();
        dohServer.close();
      }
    });

    test('uses DoH when a system TCP attempt stalls', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadAddress = InternetAddress('192.0.2.1');
      final started = Completer<void>();
      final pendingSocket = Completer<Socket>();
      var connectorCancelled = false;
      var dohLookups = 0;

      try {
        final task = await ApiClient.connectApiSocket(
          Uri.parse('https://example.test:${server.port}'),
          systemConnectBudget: const Duration(milliseconds: 30),
          resolve: (_) async => [deadAddress],
          startConnect: (address, port) async {
            if (address != deadAddress) return Socket.startConnect(address, port);
            started.complete();
            return ConnectionTask.fromSocket(pendingSocket.future, () {
              connectorCancelled = true;
              if (!pendingSocket.isCompleted) {
                pendingSocket.completeError(const SocketException('cancelled'));
              }
            });
          },
          resolveDoh: (_) async {
            dohLookups++;
            return [server.address];
          },
          secure: (socket, _) async {
            socket.close();
            return _FakeSecureSocket();
          },
        );

        await started.future;
        await task.socket.timeout(const Duration(seconds: 1));

        expect(connectorCancelled, isTrue);
        expect(dohLookups, 1);
      } finally {
        server.close();
      }
    });

    test('destroys a TLS handshake that completes after its timeout', () async {
      final systemServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final dohServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final delayedHandshake = Completer<SecureSocket>();
      final lateSecureSocket = _FakeSecureSocket();
      var handshakes = 0;

      try {
        final task = await ApiClient.connectApiSocket(
          Uri.parse('https://example.test:${systemServer.port}'),
          systemConnectBudget: const Duration(milliseconds: 30),
          resolve: (_) async => [systemServer.address],
          startConnect: (address, port) => Socket.startConnect(
            address,
            address == systemServer.address ? systemServer.port : port,
          ),
          resolveDoh: (_) async => [dohServer.address],
          secure: (socket, _) async {
            socket.close();
            handshakes++;
            if (handshakes == 1) return delayedHandshake.future;
            return _FakeSecureSocket();
          },
        );

        await task.socket.timeout(const Duration(seconds: 1));
        expect(lateSecureSocket.destroyCalls, 0);

        delayedHandshake.complete(lateSecureSocket);
        await Future<void>.delayed(Duration.zero);

        expect(lateSecureSocket.destroyCalls, 1);
      } finally {
        systemServer.close();
        dohServer.close();
      }
    });

    test('does not send local development HTTP hosts to public DoH', () async {
      var dohLookups = 0;
      final task = await ApiClient.connectApiSocket(
        Uri.parse('http://example.test:80'),
        resolve: (_) async => throw const SocketException('DNS unavailable'),
        resolveDoh: (_) async {
          dohLookups++;
          return [InternetAddress('203.0.113.30')];
        },
      );

      await expectLater(task.socket, throwsA(isA<SocketException>()));
      expect(dohLookups, 0);
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

class _FakeSecureSocket implements SecureSocket {
  int destroyCalls = 0;

  @override
  Future<Socket> close() async => this;

  @override
  void destroy() {
    destroyCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
