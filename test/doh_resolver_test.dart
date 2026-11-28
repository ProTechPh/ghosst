import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/doh_resolver.dart';

void main() {
  group('DohResolver.addressesFromResponse', () {
    test('keeps valid A and AAAA answers and ignores other records', () {
      final addresses = DohResolver.addressesFromResponse({
        'Status': 0,
        'Answer': [
          {'type': 5, 'data': 'alias.example.test.'},
          {'type': 1, 'data': '203.0.113.10'},
          {'type': 28, 'data': '2001:db8::10'},
          {'type': 1, 'data': 'not-an-ip'},
        ],
      });

      expect(addresses.map((address) => address.address), [
        '203.0.113.10',
        '2001:db8::10',
      ]);
    });

    test('rejects unsuccessful and truncated DNS responses', () {
      expect(
        DohResolver.addressesFromResponse({
          'Status': 3,
          'Answer': [
            {'type': 1, 'data': '203.0.113.10'},
          ],
        }),
        isEmpty,
      );
      expect(
        DohResolver.addressesFromResponse({
          'Status': 0,
          'TC': true,
          'Answer': [
            {'type': 1, 'data': '203.0.113.10'},
          ],
        }),
        isEmpty,
      );
    });
  });

  group('DohResolver.resolve', () {
    test('tries Google when Cloudflare is unreachable', () async {
      final requests = <Uri>[];

      final addresses = await DohResolver.resolve(
        'ghossthub.com',
        clientFactory: (_) => HttpClient(),
        query: (uri) async {
          requests.add(uri);
          if (uri.host == 'cloudflare-dns.com') {
            throw const SocketException('connection refused');
          }
          return {
            'Status': 0,
            'Answer': uri.queryParameters['type'] == 'A'
                ? [
                    {'type': 1, 'data': '203.0.113.20'},
                  ]
                : [],
          };
        },
      );

      expect(addresses.single.address, '203.0.113.20');
      expect(requests.first.host, 'cloudflare-dns.com');
      expect(requests.last.host, 'dns.google');
      expect(requests.first.queryParameters['name'], 'ghossthub.com');
      expect(
        requests.where((uri) => uri.host == 'dns.google').map((uri) => uri.queryParameters['type']),
        ['A', 'AAAA'],
      );
    });

    test('keeps both address families for IPv6-only fallback', () async {
      final addresses = await DohResolver.resolve(
        'ghossthub.com',
        clientFactory: (_) => HttpClient(),
        query: (uri) async => {
          'Status': 0,
          'Answer': uri.queryParameters['type'] == 'A'
              ? [
                  {'type': 1, 'data': '203.0.113.40'},
                ]
              : [
                  {'type': 28, 'data': '2001:db8::40'},
                ],
        },
      );

      expect(addresses.map((address) => address.address), [
        '203.0.113.40',
        '2001:db8::40',
      ]);
    });

    test('tries AAAA when the A answer is empty', () async {
      final requests = <Uri>[];

      final addresses = await DohResolver.resolve(
        'ghossthub.com',
        clientFactory: (_) => HttpClient(),
        query: (uri) async {
          requests.add(uri);
          return {
            'Status': 0,
            'Answer': uri.queryParameters['type'] == 'AAAA'
                ? [
                    {'type': 28, 'data': '2001:db8::20'},
                  ]
                : [],
          };
        },
      );

      expect(addresses.single.address, '2001:db8::20');
      expect(requests.map((uri) => uri.queryParameters['type']), ['A', 'AAAA']);
    });

    test('closes a stalled provider before trying the next one', () async {
      final started = Completer<void>();
      final stalled = Completer<Map<String, dynamic>>();
      final cloudflare = _TrackingHttpClient();
      final google = _TrackingHttpClient();
      final requests = <Uri>[];

      final pending = DohResolver.resolve(
        'ghossthub.com',
        providerTimeout: const Duration(milliseconds: 30),
        clientFactory: (addresses) =>
            addresses.first.address == '1.1.1.1' ? cloudflare : google,
        query: (uri) {
          requests.add(uri);
          if (uri.host == 'cloudflare-dns.com') {
            if (!started.isCompleted) started.complete();
            return stalled.future;
          }
          return Future.value({
            'Status': 0,
            'Answer': uri.queryParameters['type'] == 'A'
                ? [
                    {'type': 1, 'data': '203.0.113.50'},
                  ]
                : [],
          });
        },
      );

      await started.future;
      final addresses = await pending.timeout(const Duration(seconds: 1));

      expect(addresses.single.address, '203.0.113.50');
      expect(cloudflare.closeCalls, 1);
      expect(google.closeCalls, 1);
      expect(
        requests.where((uri) => uri.host == 'cloudflare-dns.com'),
        hasLength(1),
      );
    });

    test('fails clearly after both providers fail', () async {
      await expectLater(
        DohResolver.resolve(
          'ghossthub.com',
          clientFactory: (_) => HttpClient(),
          query: (_) async => throw const SocketException('offline'),
        ),
        throwsA(
          isA<SocketException>().having(
            (error) => error.message,
            'message',
            contains('DoH resolution failed for ghossthub.com'),
          ),
        ),
      );
    });
  });
}

class _TrackingHttpClient implements HttpClient {
  int closeCalls = 0;

  @override
  void close({bool force = false}) {
    closeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
