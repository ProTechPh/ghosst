# Premium shop in the app (view-only) — design

Date: 2026-11-10
Status: draft for approval

## Intent

Show the website's premium products (game keys with ₱ prices) inside the app's
Store tab. Buying stays on ghossthub.com; in-app checkout is not built yet.

## Goals

- The Store tab gains a "Premium shop" section below the coin products.
- Products come from the website DB (`products` + unused `keys`), read-only.
- Tapping a card opens that product's `checkout.php?product=<id>` in the browser.
- No coin or stock mutation in the app.

## Non-goals

- In-app checkout / payments.
- Website accounts tab (`account_products`), cart, search, filters.
- A dedicated premium screen or a new bottom-nav tab.

## Constraints

- Website keys and app products live in the same MySQL DB, so the app API can
  read them directly; no scraping.
- Website login is separate from the app account (`users` vs `app_users`). The
  website handles sign-in and checkout after the hand-off.
- `ghosst-web/` is the deploy source for the site and API (repo `api/` was moved
  there); the new route must be uploaded with the API.

## Approaches considered

1. Third shelf segment `Keys | Apps | Premium` — rejected: mixes coin and peso
   checkout in one list and hides the items behind a mode.
2. Inline section in the Store scroll — picked: visible immediately, one tap to
   buy, no new nav or screen.
3. Entry card to a dedicated screen — rejected: extra tap, extra screen.

## How

### API

- New `GET /v1/premium-shop` (public, cached) in `ghosst-web/api`.
- Query: active, non-maintenance products joined to unused `keys`, min/max price,
  `HAVING min_price > 0`, ordered by game then price.
- Response:
  `{ok, currency, products: [{id, name, game, platform, price, priceMax, image, url}]}`.
- `image` absolute (`SHOP_URL` + ltrim); `url` is `SHOP_URL/checkout.php?product=id`.
- `currency` from `settings.currency_symbol` (fallback `₱`). New `SHOP_URL`
  constant in `api/config.php`, default `https://ghossthub.com`.

### App

- `ShopItem` model with `fromJson` and `priceLabel` in `lib/services/models.dart`.
- `Backend.premiumShop()` in `worker_backend.dart` (GET `/premium-shop`, maps JSON).
- `store_screen.dart`: fetch in parallel with the coin load; hide the section on
  failure. Section header "Premium shop" with a "pay on site" hint and a
  horizontal rail of cards (image, game, name, ₱ price, "Buy on site"). The rail
  scrolls through every product, so there is no separate "view all" link.
- Tap opens the item URL with `launchUrl(..., LaunchMode.externalApplication)`.
- Section renders on both flavors; copy notes in-app checkout is coming soon.

## Edge cases

- API down / non-200 → section hidden, coin store unaffected.
- Missing image → same placeholder fallback as other cards.
- Out of stock → excluded by the query (requires an unused key).

## Verification

- `flutter analyze`, `flutter test` (new `test/shop_item_test.dart`: parsing and
  price label).
- Manual: run the local API, open Store, confirm cards, tap opens checkout in
  the browser.
- Deploy: upload `api/config.php`, `api/index.php`, `api/routes/shop.php` to
  `public_html/api/` on Hostinger.
