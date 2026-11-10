import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/models.dart';

void main() {
  test('parses a game with its image carousel and products', () {
    final game = ShopGame.fromJson({
      'name': 'BLOODSTRIKE',
      'slug': 'bloodstrike',
      'description': 'Bloodstrike cheat',
      'price': 50,
      'priceMax': 1500,
      'stock': 42,
      'currency': '₱',
      'image': 'https://ghossthub.com/uploads/hero.jpg',
      'images': [
        'https://ghossthub.com/uploads/hero.jpg',
        'https://ghossthub.com/uploads/p1.jpg',
      ],
      'products': [
        {
          'id': 65,
          'name': 'GHOSST BLOODSTRIKE',
          'platform': 'android',
          'price': 50,
          'priceMax': 1500,
          'stock': 42,
          'currency': '₱',
          'image': 'https://ghossthub.com/uploads/p1.jpg',
          'url': 'https://ghossthub.com/checkout.php?product=65',
        },
      ],
    });

    expect(game.name, 'BLOODSTRIKE');
    expect(game.images.length, 2);
    expect(game.stock, 42);
    expect(game.priceLabel, '₱50 – ₱1,500');
    expect(game.products.single.name, 'GHOSST BLOODSTRIKE');
    expect(game.products.single.url, contains('product=65'));
    expect(game.products.single.platformLabel, 'Android');
  });

  test('price label groups thousands and keeps cents', () {
    expect(shopPriceLabel('₱', 620, 1200), '₱620 – ₱1,200');
    expect(shopPriceLabel('₱', 99.5, 99.5), '₱99.50');
    expect(shopPriceLabel('₱', 200, 200), '₱200');
  });

  test('parses a version detail with description, details and gallery', () {
    final p = ShopProduct.fromJson({
      'id': 55,
      'name': 'GHOSST PREMIUM V4',
      'platform': 'android',
      'description': 'Safe main account',
      'details': 'Line one\nLine two',
      'gallery': [
        'https://ghossthub.com/uploads/a.jpg',
        'https://ghossthub.com/uploads/b.jpg',
      ],
      'price': 50,
      'priceMax': 3000,
      'stock': 6,
      'currency': '₱',
      'url': 'https://ghossthub.com/checkout.php?product=55',
    });

    expect(p.description, 'Safe main account');
    expect(p.details, contains('Line two'));
    expect(p.gallery.length, 2);
    expect(p.priceLabel, '₱50 – ₱3,000');
  });

  test('defaults missing game fields and platforms', () {
    final game = ShopGame.fromJson({});
    expect(game.name, '');
    expect(game.images, isEmpty);
    expect(game.products, isEmpty);
    expect(game.priceLabel, '₱0');
    expect(ShopProduct.fromJson({'platform': 'ios'}).platformLabel, 'iOS');
    expect(
      ShopProduct.fromJson({'platform': 'both'}).platformLabel,
      'Android + iOS',
    );
  });
}
