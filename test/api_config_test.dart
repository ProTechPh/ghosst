import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/api/api_config.dart';

void main() {
  group('ApiConfig', () {
    test('uses ghossthub.com as the only default API host', () {
      expect(ApiConfig.baseUrl, 'https://ghossthub.com/api/v1');
    });

    test('resolves relative media keys through the API host', () {
      expect(
        ApiConfig.publicUrl('uploads/products/example.jpg'),
        'https://ghossthub.com/uploads/products/example.jpg',
      );
    });
  });
}
