# Premium shop in the app (view-only) — design

Date: 2026-11-10
Status: implemented (revised after first UI pass)

## Intent

Show the website's premium products (game keys with ₱ prices) inside the app's
Store tab as a third shelf. Buying stays on ghossthub.com; in-app checkout is
not built yet.

## Goals

- The Store shelf switch becomes `Keys | Apps | Premium`.
- Premium lists **game categories** (CODM, Bloodstrike, MLBB, ...), each with
  hero art, price range, version count, and key stock.
- Tapping a game opens a read-only game page: image carousel, description,
  price range, stock, and every version with its own price/stock.
- Tapping a version opens a checkout-like page: gallery carousel, name,
  description, details, platform, stock, price. Its Buy button opens
  `checkout.php?product=<id>`. No coin or stock mutation in the app.

## Non-goals

- In-app checkout / payments.
- Website accounts tab (`account_products`), cart, search, platform filters.
- A new bottom-nav tab.

## Constraints

- Website keys and app products live in the same MySQL DB, so the app API reads
  them directly; no scraping.
- Website login is separate from the app account (`users` vs `app_users`). The
  website handles sign-in and checkout after the hand-off.
- `ghosst-web/` is the deploy source for the site and API; API edits must be
  uploaded with the app change.

## How

### API

- `GET /v1/premium-shop` (public, cached 60s) in `ghosst-web/api`.
- Query: active, non-maintenance products with at least one unused key priced
  above zero; min/max price and stock per product.
- Games meta comes from `games` (slug, description, hero image, sort order);
  a product with no games row still appears under its `game_name`.
- Response:
  `{ok, currency, games: [{name, slug, description, image, images[], price,
  priceMax, stock, currency, products: [{id, name, platform, price, priceMax,
  stock, currency, image, url}]}]}`
- `images` = game hero + that game's product images (deduped, max 8).
- `image`/`images`/`url` are absolute using `SHOP_URL` (trailing slashes
  trimmed); `url` is `SHOP_URL/checkout.php?product=<id>`.
- Games sorted by `games.sort_order`, then name.
- `GET /v1/premium-shop/{id}` returns one product with its gallery
  (`product_gallery`, fallback to the product image), plain-text
  `description`/`details`, price range, stock and checkout URL. Missing or
  out-of-stock product → 404.

### App

- Models: `ShopGame` (with `images`, `products`, `priceLabel`) and
  `ShopProduct` (`platformLabel`, `priceLabel`, plus `description`, `details`,
  `gallery` on the detail response) in `lib/services/models.dart`.
- `Backend.premiumShop()` → `GET /premium-shop`; `Backend.premiumProduct(id)`
  → `GET /premium-shop/{id}`.
- `store_screen.dart`: third segment item; the Premium shelf hides the coin
  balance/products/sponsored blocks and renders game cards (hero, name, price
  range, versions + stock). A failed or empty feed shows an "unavailable" state
  with a link to `browseproducts.php`; the coin shelves are unaffected.
- New `lib/screens/premium_game_screen.dart`: PageView image carousel with
  dots, game description, price/stock, version rows (image, platform, stock,
  price, View). Tapping a row opens the product page.
- New `lib/screens/premium_product_screen.dart`: the checkout-like page
  (carousel from `product_gallery`, name, category, platform, stock, price,
  About/Details, sticky "Buy on ghossthub.com"). Details load lazily from the
  product endpoint; the feed row is shown instantly.
- `PremiumCarousel` (`lib/screens/premium_carousel.dart`) is shared by both.
- Section renders on both flavors.

## Edge cases

- API down / non-200 → Premium tab shows the unavailable state; coin shelves
  still work.
- Missing game hero → first product image; no images at all → controller icon.
- Sold out → excluded by the query (requires an unused priced key).
- Malformed/relative product URL → tap does nothing (host check).

## Verification

- `flutter analyze`, `flutter test` (`test/premium_shop_test.dart`: game +
  nested product parsing, price label grouping/cents, defaults).
- Live: upload `api/index.php` + `api/routes/shop.php`, then
  `curl https://ghossthub.com/api/v1/premium-shop` → `games[]` with images and
  checkout URLs, and `curl .../premium-shop/55` → gallery + details.
- Device: Premium shelf lists games, game carousel swipes, a version opens the
  product page with gallery/description, Buy opens the browser.
