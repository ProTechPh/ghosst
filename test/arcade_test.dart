import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/arcade.dart';
import 'package:ghosst/services/models.dart';

Product _p({
  int cost = 100,
  String type = 'key',
  String version = '',
  String fileSize = '',
  List<ProductDuration> durations = const [],
}) => Product(
  id: 'p1',
  name: 'X',
  cost: cost,
  active: true,
  type: type,
  version: version,
  fileSize: fileSize,
  durations: durations,
);

void main() {
  test('tierForCost thresholds', () {
    expect(tierForCost(0), RarityTier.standard);
    expect(tierForCost(499), RarityTier.standard);
    expect(tierForCost(500), RarityTier.plus);
    expect(tierForCost(1499), RarityTier.plus);
    expect(tierForCost(1500), RarityTier.prime);
    expect(tierForCost(2999), RarityTier.prime);
    expect(tierForCost(3000), RarityTier.vault);
    expect(tierForCost(50000), RarityTier.vault);
  });

  test('unknown stock is not sold out', () {
    expect(isSoldOutCard(isKey: true, stock: 0), isTrue);
    expect(isSoldOutCard(isKey: true, stock: -1), isFalse); // not loaded yet
    expect(isSoldOutCard(isKey: true, stock: 3), isFalse);
    expect(isSoldOutCard(isKey: false, stock: 0), isFalse); // downloads never sell out
  });

  test('entryCost uses the cheapest duration', () {
    expect(
      entryCost(
        _p(
          cost: 900,
          durations: const [
            ProductDuration(label: '7d', cost: 900),
            ProductDuration(label: '30d', cost: 300),
          ],
        ),
      ),
      300,
    );
    expect(entryCost(_p(cost: 700)), 700);
  });

  test('cardMeta never renders blank', () {
    expect(cardMeta(_p()), 'License key');
    expect(cardMeta(_p(type: 'apk', version: '1.2.3')), 'APK 1.2.3');
    expect(cardMeta(_p(type: 'apk')), 'APK');
    expect(cardMeta(_p(type: 'file', fileSize: '12 MB')), 'FILE · 12 MB');
    expect(cardMeta(_p(type: 'file')), 'FILE');
  });

  test('cardType is the index strip label', () {
    expect(cardType(_p()), 'KEY');
    expect(cardType(_p(type: 'apk')), 'APK');
    expect(cardType(_p(type: 'file')), 'FILE');
  });
}
