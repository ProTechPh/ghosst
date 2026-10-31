import 'services/models.dart';

/// Price tier. Derived at render time; never stored on the product.
enum RarityTier { standard, plus, prime, vault }

RarityTier tierForCost(int cost) {
  if (cost < 500) return RarityTier.standard;
  if (cost < 1500) return RarityTier.plus;
  if (cost < 3000) return RarityTier.prime;
  return RarityTier.vault;
}

/// Lowest selectable price — shelf and detail page must agree on the tier.
int entryCost(Product p) => p.hasDurations
    ? p.durations.map((d) => d.cost).reduce((a, b) => a < b ? a : b)
    : p.cost;

/// `-1` means stock is unknown (non-key product or not fetched yet).
bool isSoldOutCard({required bool isKey, required int stock}) =>
    isKey && stock == 0;

String cardMeta(Product p) {
  if (p.isKey) return 'License key';
  if (p.isApk) return p.version.isEmpty ? 'APK' : 'APK ${p.version}';
  return p.fileSize.isEmpty ? 'FILE' : 'FILE · ${p.fileSize}';
}

String cardType(Product p) => p.isKey ? 'KEY' : (p.isApk ? 'APK' : 'FILE');
