# Custom manual payment methods on the website — design

**Date:** 2026-11-27
**Status:** awaiting approval

## Intent / why

The owner wants to offer more manual deposit channels (e.g. GoTyme in addition
to GCash/PayPal) without editing PHP each time. An admin should be able to add
a method with a name and account number, toggle it, and remove it; customers
then see it on the top-up page and can submit a receipt for manual approval.

## Goals

1. Admin section "Custom manual methods" with add / edit name, number, optional
   note, enable toggle, delete, and Save.
2. Top-up page lists enabled custom methods alongside QRPh, GCash, PayPal, and
   shows their account name/number/note with a copy button.
3. Receipt submission accepts only enabled custom methods; stored
   `payment_method` value is a stable slug (e.g. `gotyme`) in the existing
   `VARCHAR(50)` column.
4. Admin dashboard shows a friendly label instead of a raw slug.
5. No DB migration: configuration lives in the existing `settings` key/value
   table as one JSON string.

## Non-goals / anti-goals

- No new payment gateway, no PayMongo/auto-credit path for custom methods —
  they are **manual receipt + admin approval** only.
- No Flutter/app changes. The website top-up page is the only customer surface.
- No changes to QRPh, GCash, or PayPal behavior; no custom method may reuse the
  reserved keys `qrph`, `gcash`, `paypal`.
- No per-method images/logos, ordering beyond insertion order, or bulk import.

## Constraints

- Website files live in gitignored `ghosst-web/`; they are uploaded to
  Hostinger manually, not built/tested from the Flutter repo.
- `settings` is key/value (`setting_key`, `setting_value`); `admin/settings.php`
  already saves arbitrary scalar `settings[...]` keys with a generic loop.
- `topup_requests.payment_method` is `VARCHAR(50)` — no schema change needed.
- Current hardcoded allowlists: `upload_receipt.php` (`gcash`, `paypal`) and
  `process-payment.php` (`qrph`, `paypal`). Only the manual receipt handler
  needs to learn custom methods.
- Escaping: all values rendered with `htmlspecialchars`; JS config injected
  with `json_encode(..., JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)`.

## Approaches

Chosen: **one `settings` key holding a JSON array**, with a shared PHP helper
for load/save/validation, a server-rendered admin form with JS add/remove, and
small integration edits in `topup.php`, `upload_receipt.php`, and
`admin/dashboard.php`. No migration; smallest deployable change; the tradeoff
is that a single admin save rewrites the whole list (last save wins), which is
acceptable for a single operator.

Rejected: a new `payment_methods` table with CRUD (cleaner rows, but requires a
manual Hostinger migration and more files); cloning `gcash_*` settings keys per
method (no structure, unbounded keys, error-prone).

## Design

### 1. Shared helper — `ghosst-web/includes/ManualPaymentMethods.php`

New file, no dependency on `db_config.php`; every function takes the PDO or
plain arrays.

```php
function manual_methods_load(PDO $pdo): array
function manual_methods_save(PDO $pdo, array $methods): void
function manual_methods_parse(array $rows): array      // sanitize + validate
function manual_method_slug(string $name, array $existing): string
function manual_method_allowed(array $methods, string $key): bool
function manual_method_label(array $methods, string $key): string
```

Stored JSON shape (max 20 entries):

```json
[{"key":"gotyme","name":"GoTyme","number":"0917 123 4567","note":"Send via GoTyme app","enabled":true}]
```

Validation rules: name 1–50 chars; number 1–50; note ≤ 200; key matches
`^[a-z0-9][a-z0-9_-]{0,49}$`, unique, not in the reserved set; invalid rows are
dropped (not fatal). Slug is generated from the name on first save and kept in
a hidden field afterwards, so renaming does not break historical requests.

`manual_methods_save` upserts `settings.manual_payment_methods` with
`INSERT ... ON DUPLICATE KEY UPDATE`, same statement style as `admin/settings.php`.

### 2. Admin UI — `ghosst-web/admin/settings.php`

- Load methods with `manual_methods_load($pdo)` near the other settings reads.
- In `save_settings`, before the generic loop: if `isset($_POST['manual_methods'])`,
  run `manual_methods_parse()` and `manual_methods_save()`; unset that POST key
  so it is not written as a stray scalar setting.
- New "Custom manual methods" card inside `manualGatewaysContainer`, after the
  GCash/PayPal cards: server-rendered rows with inputs
  `manual_methods[i][key]` (hidden), `[name]`, `[number]`, `[note]`, `[enabled]`,
  and a Remove button; an "Add method" button clones a `<template>` row with a
  fresh index and empty key.
- Existing generic settings save and flash message stay unchanged.

### 3. Customer top-up page — `ghosst-web/topup.php`

- Load enabled custom methods; add them to `$anyMethodAvailable` and to the
  `$defaultMethod` fallback chain (after GCash/PayPal).
- Render one radio per enabled custom method using the existing
  `.method.nx-manual-method` markup, `data-is-auto="0"`, `data-currency="PHP"`,
  generic `bi-wallet2` icon, label = method name, `MANUAL` badge, and
  `small` = note or number.
- Inject each into `GHOSST_MANUAL_CONFIG` as `{number, name, note}`.
- In `onMethodChange()`, after the `gcash` / `paypal` branches, add a generic
  `else if (GHOSST_MANUAL_CONFIG[method])` branch rendering the same account
  card pattern (name, note, number + copy button). Summary label uses the
  method name from config.

### 4. Receipt handler — `ghosst-web/upload_receipt.php`

- Replace the fixed allowlist with `['gcash','paypal'] + enabled custom keys`.
- A disabled or unknown custom key gets the existing "Invalid payment method
  selected." error; the per-method disabled checks for GCash/PayPal stay as-is.
- No change to file validation, rate limits, insert, or Telegram notify.

### 5. Admin review — `ghosst-web/admin/dashboard.php`

- In pending and processed tables, replace the `gcash ? phone-fill : paypal`
  icon logic with: `gcash` → `phone-fill`, `paypal` → `paypal`, `qrph` →
  `qr-code-scan`, anything else → `wallet2`; label via
  `manual_method_label($methods, $key)` (falls back to `ucfirst($key)`).

### 6. Tests / verification

- PHP self-check `ghosst-web/api/tests/manual_payments_test.php` with a fake
  PDO: slug generation, reserved-key rejection, duplicate names, >20 cap,
  invalid row dropped, enabled filter, label fallback, and allowed-key check.
- Run `php tests/manual_payments_test.php` plus the existing API self-checks.
- Website has no automated browser suite here; verify by reading rendered PHP
  and, after upload, a manual admin add → top-up visible → receipt submit flow.

### 7. Rollout

1. Upload the changed `ghosst-web/` files (helper, `admin/settings.php`,
   `topup.php`, `upload_receipt.php`, `admin/dashboard.php`) to Hostinger.
2. In admin Settings → Manual Payment Methods, add e.g. GoTyme with name +
   number, enable, Save.
3. Open top-up page, select GoTyme, confirm details + copy button, submit a
   small test receipt, approve it from admin dashboard.

## Left to the builder

Exact CSS classes for the new admin rows, the JS template markup, and small UI
copy are builder calls. The owner picked Option 1; no further product choice is
open.
