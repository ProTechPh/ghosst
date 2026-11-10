# Premium Shop in the Store Tab — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the website's premium game-key products (₱ prices, read-only) in the app's Store tab, with each card opening the product's checkout page in the browser.

**Architecture:** A new public `GET /v1/premium-shop` route in the PHP API reads the shop tables (`products` + unused `keys`) from the same MySQL DB and returns a small JSON feed with absolute image and checkout URLs. The Flutter app maps it to `ShopItem`, and the Store screen renders a horizontal rail below the coin products. Nothing is bought or mutated in the app.

**Tech Stack:** PHP 8.1+ (PDO MySQL) for the API; Flutter/Dart, `dio`, `cached_network_image`, `url_launcher` for the app.

**Spec:** `docs/superpowers/specs/2026-11-10-premium-shop-design.md`

## Global Constraints

- API source is `ghosst-web/api/` (gitignored). The repo's old `api/` tree is gone; do not recreate it.
- Shop prices are website pesos (₱). Never render them with coin components (`entryCost`, `CardFrame`, `RarityTier`) or add them to the wallet.
- The premium feed is optional content: if it fails, the Store must still render the coin products normally.
- Follow existing app patterns: network calls only in `lib/services/worker_backend.dart`, models in `lib/services/models.dart`, theme tokens from `lib/theme.dart`.
- The working tree has unrelated user changes. Stage only the files named in each task.
- Local PHP CLI has no `pdo_mysql`, so the route is syntax-checked locally and smoke-tested after upload.

## Review Focus

- Shop API down or slow → Store still shows coin products; no error screen or stuck spinner (Task 3, manual check).
- Zero premium products → header and rail absent, no empty band (Task 3, `if (premium.isNotEmpty)` guard).
- Product with no `image_path`/`hero_image_path` or a 404 image → placeholder tile, no crash (Task 3, conditional + `errorWidget`).
- Prices with cents or a min/max spread → `₱99.50`, `₱620 – ₱1,200`, never `₱620.0` (Task 2 tests).
- Malformed/relative product URL → tap does nothing instead of crashing (Task 3, `Uri.tryParse` + host check).

---

### Task 1: Premium shop API route

**Files:**
- Modify: `ghosst-web/api/config.php` (add `SHOP_URL` near `PUBLIC_CDN`)
- Create: `ghosst-web/api/routes/shop.php`
- Modify: `ghosst-web/api/index.php` (ROUTES entry + public cache header)

**Interfaces:**
- Consumes: `all_rows()`, `scalar()` from `ghosst-web/api/lib/db.php`; `SHOP_URL`.
- Produces: `GET /v1/premium-shop` →
  `{"ok":true,"currency":"₱","products":[{"id":57,"name":"AEGISGC3","game":"CALL OF DUTY MOBILE","platform":"ios","price":620,"priceMax":620,"image":"https://ghossthub.com/uploads/...","url":"https://ghossthub.com/checkout.php?product=57"}]}`

- [ ] **Step 1: Add the storefront constant**

In `ghosst-web/api/config.php`, after the `PUBLIC_CDN` define, add:

```php
/** Public storefront, for premium-shop links and images. */
define('SHOP_URL', getenv('GHOSST_SHOP_URL') ?: 'https://ghossthub.com');
```

- [ ] **Step 2: Create `ghosst-web/api/routes/shop.php`**

`premium_shop_list(array $ctx): array` returns the feed. Query: active, non-maintenance products with at least one unused key priced above zero; min/max price from unused keys; ordered by game then price. Build absolute `image` (`SHOP_URL` + `ltrim(path)`, keep already-absolute URLs) and `url` (`SHOP_URL . '/checkout.php?product=' . id`). `currency` comes from `settings.currency_symbol`, fallback `'₱'`. Each product row carries `currency` too, so the app needs only one model.

```php
<?php
declare(strict_types=1);

/** Read-only feed ng website premium shop (game keys, ₱ prices). */
function premium_shop_list(array $ctx): array
{
    $rows = all_rows(
        'SELECT p.id, p.name, p.game_name, p.platform, p.image_path, p.hero_image_path,
                (SELECT MIN(k.price) FROM `keys` k
                  WHERE k.product_id = p.id AND k.is_used = 0 AND k.price > 0) AS min_price,
                (SELECT MAX(k.price) FROM `keys` k
                  WHERE k.product_id = p.id AND k.is_used = 0 AND k.price > 0) AS max_price
           FROM products p
          WHERE p.is_active = 1 AND p.is_maintenance = 0
            AND EXISTS (SELECT 1 FROM `keys` k
                         WHERE k.product_id = p.id AND k.is_used = 0 AND k.price > 0)
          ORDER BY p.game_name ASC, min_price ASC'
    );

    $currency = (string) (scalar(
        "SELECT setting_value FROM settings WHERE setting_key = 'currency_symbol'"
    ) ?: '₱');

    $products = [];
    foreach ($rows as $r) {
        $img = (string) ($r['image_path'] ?: $r['hero_image_path']);
        if ($img !== '' && !preg_match('#^https?://#i', $img)) {
            $img = SHOP_URL . '/' . ltrim($img, '/');
        }
        $products[] = [
            'id'       => (int) $r['id'],
            'name'     => (string) $r['name'],
            'game'     => (string) ($r['game_name'] ?? ''),
            'platform' => (string) $r['platform'],
            'price'    => (float) $r['min_price'],
            'priceMax' => (float) $r['max_price'],
            'currency' => $currency,
            'image'    => $img,
            'url'      => SHOP_URL . '/checkout.php?product=' . (int) $r['id'],
        ];
    }

    return ['ok' => true, 'currency' => $currency, 'products' => $products];
}
```

- [ ] **Step 3: Register the route**

In `ghosst-web/api/index.php`, after the public `GET /v1/products` lines, add:

```php
    ['GET',    '#^/v1/premium-shop$#',                     'premium_shop_list',       'none'],
```

- [ ] **Step 4: Cache the public feed**

In `ghosst-web/api/index.php`, add a branch next to the existing products one (leave the products values untouched):

```php
    if ($method === 'GET' && $path === '/v1/premium-shop' && header_value('authorization') === '') {
        header('cache-control: public, max-age=60, stale-while-revalidate=300');
    } elseif ($method === 'GET' && str_starts_with($path, '/v1/products') && header_value('authorization') === '') {
        header('cache-control: public, max-age=30, stale-while-revalidate=120');
    }
```

- [ ] **Step 5: Syntax-check**

Run: `php -l ghosst-web/api/config.php; php -l ghosst-web/api/routes/shop.php; php -l ghosst-web/api/index.php`
Expected: `No syntax errors detected` three times.

---

### Task 2: `ShopItem` model and backend call

**Files:**
- Create: `test/shop_item_test.dart`
- Modify: `lib/services/models.dart` (append `ShopItem`)
- Modify: `lib/services/worker_backend.dart` (add `premiumShop()` in the `// ---- store ----` section)

**Interfaces:**
- Consumes: the Task 1 JSON.
- Produces: `class ShopItem` with `id, name, game, platform, price, priceMax, currency, image, url`, `ShopItem.fromJson(Map<String, dynamic>)`, `String get priceLabel`; `Backend.premiumShop() → Future<List<ShopItem>>`.

- [ ] **Step 1: Write the failing tests**

Create `test/shop_item_test.dart`:

```dart
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
    final item = ShopItem.fromJson({'price': 99.5, 'priceMax': 99.5, 'currency': '₱'});

    expect(item.priceLabel, '₱99.50');
    expect(item.id, 0);
    expect(item.name, '');
    expect(item.game, '');
    expect(item.image, '');
    expect(item.url, '');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/shop_item_test.dart`
Expected: FAIL — `ShopItem isn't defined`.

- [ ] **Step 3: Implement `ShopItem`**

Append to `lib/services/models.dart`:

```dart
/// One website premium-shop product (game key, priced in ₱). Read-only: the
/// app never buys these; [url] opens the site's checkout page.
class ShopItem {
  const ShopItem({
    required this.id,
    required this.name,
    required this.game,
    required this.platform,
    required this.price,
    required this.priceMax,
    required this.currency,
    required this.image,
    required this.url,
  });

  factory ShopItem.fromJson(Map<String, dynamic> json) => ShopItem(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: json['name'] as String? ?? '',
    game: json['game'] as String? ?? '',
    platform: json['platform'] as String? ?? '',
    price: (json['price'] as num?)?.toDouble() ?? 0,
    priceMax: (json['priceMax'] as num?)?.toDouble() ?? 0,
    currency: json['currency'] as String? ?? '₱',
    image: json['image'] as String? ?? '',
    url: json['url'] as String? ?? '',
  );

  final int id;
  final String name;
  final String game;
  final String platform;
  final double price;
  final double priceMax;
  final String currency;
  final String image;
  final String url;

  /// `₱620` or `₱620 – ₱1,200` when keys are priced differently.
  String get priceLabel {
    String money(double v) {
      final whole = v == v.roundToDouble();
      final digits = whole ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
      return digits.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (m) => ',',
      );
    }

    final low = '$currency${money(price)}';
    return priceMax > price ? '$low – $currency${money(priceMax)}' : low;
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/shop_item_test.dart`
Expected: all 3 tests PASS.

- [ ] **Step 5: Add `Backend.premiumShop()`**

In `lib/services/worker_backend.dart`, in the `// ---- store ----` section:

```dart
/// Website premium shop (read-only; buying finishes on ghossthub.com).
static Future<List<ShopItem>> premiumShop() async {
  final res = await _api.get('/premium-shop');
  final currency = res['currency'] as String? ?? '₱';
  return (res['products'] as List? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((j) => ShopItem.fromJson({...j, 'currency': currency}))
      .toList();
}
```

- [ ] **Step 6: Analyze**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 7: Commit**

```bash
git add lib/services/models.dart lib/services/worker_backend.dart test/shop_item_test.dart
git commit -m "feat: add premium shop model and backend call"
```

---

### Task 3: Premium shop section in the Store tab

**Files:**
- Modify: `lib/screens/store_screen.dart`

**Interfaces:**
- Consumes: `Backend.premiumShop()`, `ShopItem`.
- Produces: nothing other tasks use.

- [ ] **Step 1: Add the import, state, and loader**

- Add `import 'package:url_launcher/url_launcher.dart';`.
- Add `List<ShopItem> premium = const [];` next to `products`.
- In `_load()`, before the coin try/catch, add `unawaited(_loadPremium());` so pulls and tab refreshes update it in parallel.
- Add:

```dart
Future<void> _loadPremium() async {
  try {
    final items = await Backend.premiumShop();
    if (mounted) setState(() => premium = items);
  } catch (e) {
    // Optional content: keep the last good list, never block the coin store.
    debugPrint('[Store] premium shop unavailable: $e');
  }
}
```

- [ ] **Step 2: Render the section**

Insert between the coin-products block and the `// ---- sponsored native ad` block in `build()`, outside the `Distribution.showsDownloadStore` gate so both flavors show it:

```dart
if (premium.isNotEmpty) ...[
  const SectionHeader(title: 'Premium shop'),
  const SizedBox(height: AppSpace.xs),
  Text('Buy on ghossthub.com - in-app checkout is coming soon.',
      style: AppText.caption),
  const SizedBox(height: AppSpace.md),
  ScrollReveal(child: _premiumShelf()),
  const SizedBox(height: AppSpace.xl),
],
```

- [ ] **Step 3: Build the rail and cards**

`_premiumShelf()` → `SizedBox(height: 248, child: ListView.separated(scrollDirection: Axis.horizontal, ...))` with `AppSpace.md` gaps. 248 fits two-line names at the app's 1.3 max text scale; the text block below the image sits in an `Expanded` with `Spacer()` before the buy row so a long name ellipsizes instead of overflowing.

`_premiumCard(ShopItem item)` → `Pressable(onTap: () => _openPremium(item))` around a `Container(width: 168)` using `AppColors.surface`, `AppColors.border`, `AppRadius.card`:

- Top image 96 high, `ClipRRect`: `CachedNetworkImage` (`memCacheWidth: 400`, `errorWidget` placeholder) when `item.image` is non-empty, else a placeholder tile (`AppColors.surfaceHigh` + `Icons.storefront_outlined`). Wrap in `Semantics(image: true, label: item.name)`.
- Below, padded 10: game name (10 px, `AppColors.cyan`, one line, ellipsis), product name (`AppText.subtitle`, 13 px, two lines, ellipsis), `item.priceLabel` (`AppText.figure`, `AppColors.gold`), and a `Buy on site` row (10 px `AppColors.textDim` + `CupertinoIcons.arrow_up_right` at 12).

`_openPremium(ShopItem item)`:

```dart
Future<void> _openPremium(ShopItem item) async {
  final uri = Uri.tryParse(item.url);
  if (uri == null || uri.host.isEmpty) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
```

Do not use `CardFrame`, `tierForCost`, or any coin widget on these cards.

- [ ] **Step 4: Analyze and test**

Run: `flutter analyze; flutter test`
Expected: no analyzer issues; all existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/store_screen.dart
git commit -m "feat: show website premium shop in store tab"
```

---

### Task 4: Deploy handoff and verification

**Files:** none (deployment + docs).

- [ ] **Step 1: Deploy the API**

Upload to Hostinger `public_html/api/`:

- `config.php` (new `SHOP_URL`)
- `index.php` (route + cache)
- `routes/shop.php` (new)

- [ ] **Step 2: Verify the live feed**

Run: `curl -s https://ghossthub.com/api/v1/premium-shop`
Expected: `"ok":true`, a `currency` of `₱`, and products whose `url` ends in `/checkout.php?product=<id>` and whose `image` starts with `https://ghossthub.com/`.

- [ ] **Step 3: Device smoke test**

`flutter run --flavor play` then open Store:

- Premium shop section appears below the coin products; prices show `₱`, never coins.
- Tapping a card opens the browser on that product's checkout page.
- Kill network / stop the API: Store still shows coin products and the section is simply absent.
- With no premium products returned, no header or empty rail appears.

- [ ] **Step 4: Commit the docs**

```bash
git add docs/superpowers/specs/2026-11-10-premium-shop-design.md docs/superpowers/plans/2026-11-10-premium-shop.md
git commit -m "docs: add premium shop spec and plan"
```
