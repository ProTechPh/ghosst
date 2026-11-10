import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/models.dart';

void main() {
  test('parses a premium shop item', () {
    final item = ShopItem.fromJson({
      'id': 57,
      'name': 'AEGISGC3',
      'game': 'CALL OF DUTY MOBILE',
      'platform': 'ios',
      'price': 620,
      'priceMax': 620,
      'currency': '₱',
      'image': 'https://ghossthub.com/uploads/a.jpg',
      'url': 'https://ghossthub.com/checkout.php?product=57',
    });

    expect(item.id, 57);
    expect(item.name, 'AEGISGC3');
    expect(item.game, 'CALL OF DUTY MOBILE');
    expect(item.price, 620);
    expect(item.image, endsWith('a.jpg'));
    expect(item.url, contains('product=57'));
    expect(item.priceLabel, '₱620');
  });

  test('price label shows a grouped range when keys differ', () {
    final item = ShopItem.fromJson({
      'price': 620,
      'priceMax': 1200,
      'currency': '₱',
    });

    expect(item.priceLabel, '₱620 – ₱1,200');
  });

  test('price label keeps cents and defaults missing fields', () {
    final item = ShopItem.fromJson({
      'price': 99.5,
      'priceMax': 99.5,
      'currency': '₱',
    });

    expect(item.priceLabel, '₱99.50');
    expect(item.id, 0);
    expect(item.name, '');
    expect(item.game, '');
    expect(item.image, '');
    expect(item.url, '');
  });
}
