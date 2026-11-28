import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/api_client.dart';

void main() {
  group('ApiClient.orderedApiAddresses', () {
    test('orders IPv4 answers before IPv6 answers', () {
      final ipv6 = InternetAddress('2606:4700:3033::6815:428e');
      final ipv4 = InternetAddress('104.21.66.142');

      final addresses = ApiClient.orderedApiAddresses([ipv6, ipv4]);

      expect(addresses, [ipv4, ipv6]);
    });

    test('keeps every address in resolver order within each family', () {
      final ipv4a = InternetAddress('104.21.66.142');
      final ipv4b = InternetAddress('172.67.204.135');
      final ipv6 = InternetAddress('2606:4700:3033::6815:428e');

      final addresses = ApiClient.orderedApiAddresses([ipv6, ipv4a, ipv4b]);

      expect(addresses, [ipv4a, ipv4b, ipv6]);
    });

    test('keeps IPv6 when the network has no IPv4 answer', () {
      final ipv6 = InternetAddress('2606:4700:3033::6815:428e');

      final addresses = ApiClient.orderedApiAddresses([ipv6]);

      expect(addresses, [ipv6]);
    });
  });
}
