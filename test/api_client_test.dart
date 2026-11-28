import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/api_client.dart';

void main() {
  group('ApiClient.preferredApiAddress', () {
    test('prefers IPv4 when a resolver returns IPv6 first', () async {
      final ipv6 = InternetAddress('2606:4700:3033::6815:428e');
      final ipv4 = InternetAddress('104.21.66.142');

      final address = await ApiClient.preferredApiAddress(
        'ghossthub.com',
        resolve: (_) async => [ipv6, ipv4],
      );

      expect(address, same(ipv4));
    });

    test('keeps IPv6 when the network has no IPv4 answer', () async {
      final ipv6 = InternetAddress('2606:4700:3033::6815:428e');

      final address = await ApiClient.preferredApiAddress(
        'ghossthub.com',
        resolve: (_) async => [ipv6],
      );

      expect(address, same(ipv6));
    });

    test('fails clearly when DNS returns no addresses', () async {
      await expectLater(
        ApiClient.preferredApiAddress(
          'ghossthub.com',
          resolve: (_) async => const [],
        ),
        throwsA(
          isA<SocketException>().having(
            (error) => error.message,
            'message',
            contains('No address for ghossthub.com'),
          ),
        ),
      );
    });
  });
}
