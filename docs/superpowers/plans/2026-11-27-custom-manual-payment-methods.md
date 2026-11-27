# Custom Manual Payment Methods Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the website admin add/remove manual payment methods (name, number, note, enabled) that appear on the top-up page and accept receipts for manual approval.

**Architecture:** A single `settings` row stores a JSON array of methods; a shared helper loads, validates, saves, and labels them. Admin settings renders editable rows, `topup.php` renders them as extra manual radios and account-detail cards, `upload_receipt.php` validates the posted slug, and the admin dashboard shows friendly labels. No schema change, no app change.

**Tech Stack:** PHP 8 on Hostinger (gitignored `ghosst-web/`), MySQL `settings` key/value table, plain-PHP self-check tests, Bootstrap-icons + vanilla JS already on the site.

**Spec:** `docs/superpowers/specs/2026-11-27-custom-manual-payment-methods-design.md`

## Global Constraints

- No DB migration. Config lives in `settings.manual_payment_methods` as JSON.
- No Flutter/app changes; no PayMongo/auto-credit for custom methods — manual receipt + admin approval only.
- No custom method may use reserved keys `qrph`, `gcash`, `paypal`.
- Max 20 methods; key matches `^[a-z0-9][a-z0-9_-]{0,49}$`; name 1–50; number 1–50; note ≤ 200.
- Custom methods obey `manual_payment_enabled` master switch; disabled/unknown key is rejected at receipt upload.
- All rendered values use `htmlspecialchars`; JS config uses `json_encode(..., JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)`; JS-card interpolation uses `escapeHtml()`/`textContent`, including `data-copy`.
- An all-invalid save is a no-op with an error, never a silent clear; removing every row is an explicit clear.
- Website files are gitignored and deployed by upload — tasks end with verification, **not** a git commit (only docs are committed).

## Review Focus

1. All-invalid save must not erase configured methods — Task 1: `all-invalid rows keep the previous list`.
2. Reserved key or duplicate slug must be rejected — Task 1: `reserved and duplicate keys are rejected`.
3. Number with quotes/punctuation must not break the copy button — Task 3: `escapeHtml is used for interpolated config values`.
4. Master switch off must hide methods and block receipts — Task 3: `custom methods are gated by manual_payment_enabled`; Task 4: `receipt validation checks manual_payment_enabled first`.
5. A disabled custom method posted by hand must be rejected — Task 4: `disabled custom method is rejected`.

---

### Task 1: Shared helper and self-check

**Files:**
- Create: `ghosst-web/includes/ManualPaymentMethods.php`
- Create: `ghosst-web/api/tests/manual_payments_test.php`

**Interfaces:**
- Consumes: PDO `settings` table (`setting_key`, `setting_value`), existing `INSERT ... ON DUPLICATE KEY UPDATE` style from `admin/settings.php`.
- Produces:
  - `manual_methods_load(PDO $pdo): array` — returns the validated list, `[]` when unset/malformed.
  - `manual_methods_save(PDO $pdo, array $methods): void`
  - `manual_methods_parse(array $rows): array` — sanitizes, drops invalid rows, caps at 20, keeps stable keys.
  - `manual_methods_parse_result(array $rows, array $previous): array` → `['methods' => array, 'error' => ?string]`; when rows were posted but all are invalid, returns `$previous` with an error message instead of an empty list.
  - `manual_method_slug(string $name, array $existing): string`
  - `manual_method_allowed(array $methods, string $key): bool` — true only for enabled, valid keys.
  - `manual_method_label(array $methods, string $key): string` — falls back to `ucfirst($key)`.
  - Stored shape: `[{"key":"gotyme","name":"GoTyme","number":"0917 123 4567","note":"...","enabled":true}]`.

- [ ] **Step 1: Write the failing tests**

In `tests/manual_payments_test.php`, define a fake PDO with a `prepare()/execute()` recorder mirroring `social_test.php`, `check()` helper, and require the new helper. Assert:
  - `manual_method_slug('GoTyme', []) === 'gotyme'`; a second `'GoTyme'` becomes `gotyme-2`.
  - `reserved and duplicate keys are rejected`: a row named `PayPal` and a row with an existing key are dropped by `manual_methods_parse()`.
  - `all-invalid rows keep the previous list`: `manual_methods_parse_result([['name' => '']], [['key'=>'gotyme','name'=>'GoTyme','number'=>'0917','note'=>'','enabled'=>true]])` returns the previous list and a non-null `error`.
  - 21 valid rows are capped to 20; a row with number `A-1 "X" <b>` survives intact (escaping is a render concern).
  - `manual_method_allowed()` is true for an enabled method, false for disabled/unknown/reserved.
  - `manual_method_label()` returns the configured display name and falls back to `ucfirst($key)`.

- [ ] **Step 2: Run it to verify it fails**

Run from `ghosst-web/api`: `php tests/manual_payments_test.php`
Expected: FAIL because the helper file does not exist.

- [ ] **Step 3: Implement the helper**

Write the seven functions in `includes/ManualPaymentMethods.php`. `manual_methods_parse_result()` compares posted rows against the parsed result so callers can distinguish "explicit empty" from "all invalid". `manual_methods_save()` uses `INSERT INTO settings (setting_key, setting_value, updated_at) VALUES (?, ?, NOW()) ON DUPLICATE KEY UPDATE setting_value = ?, updated_at = NOW()` with key `manual_payment_methods` and `json_encode(..., JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)`.

- [ ] **Step 4: Run it to verify it passes**

Run: `php tests/manual_payments_test.php`
Expected: PASS.

- [ ] **Step 5: Verify, do not commit**

`git status --short` unchanged for this task (`ghosst-web/` is gitignored).

---

### Task 2: Admin settings UI

**Files:**
- Modify: `ghosst-web/admin/settings.php` (POST handler ~33–87, settings reads ~118–123, manual gateways section ~295–383)

**Interfaces:**
- Consumes: all six Task 1 functions.
- Produces: `$_POST['manual_methods'][i][key|name|number|note|enabled]` save path; rendered rows with keys `manual-method-row-<i>`, `manual-method-add`, `manual-method-remove-<i>`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/manual_payments_test.php`: read `admin/settings.php` as a string and assert it contains `manual_methods_load($pdo)`, `manual_methods_parse(`, `manual_methods_save(`, `manual-method-add`, and `name="manual_methods[` (the row field prefix).

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/manual_payments_test.php`
Expected: FAIL on the settings.php assertions.

- [ ] **Step 3: Wire the save path and render the rows**

In `save_settings`, before the generic loop: call `manual_methods_parse_result($_POST['manual_methods'] ?? [], $previous)`, save the returned `methods` via `manual_methods_save()`, set `$flashMsg`/`$flashType` when `error` is non-null, and `unset($_POST['settings']['manual_payment_methods'])` if present so the JSON is not double-written. Load `$manualMethods` with `manual_methods_load($pdo)` alongside the other settings reads. Render a "Custom manual methods" card inside `manualGatewaysContainer` with server-rendered rows and a `<template>` row cloned by an "Add method" button; each row has hidden `key`, text `name`/`number`/`note`, checkbox `enabled`, and a Remove button.

- [ ] **Step 4: Run it to verify it passes**

Run: `php tests/manual_payments_test.php` then `php -l ghosst-web/admin/settings.php` (from repo root)
Expected: PASS and no syntax errors.

- [ ] **Step 5: Verify, do not commit**

No tracked files changed.

---

### Task 3: Top-up page integration

**Files:**
- Modify: `ghosst-web/topup.php` (config reads ~90–113, method radios ~1830–1871, `GHOSST_MANUAL_CONFIG` ~2368–2380, `onMethodChange()` ~2382–2468)

**Interfaces:**
- Consumes: `manual_methods_load()`, `manual_method_allowed()`; existing `$manualPaymentEnabled`, `$defaultMethod`, `$anyMethodAvailable`, `GHOSST_MANUAL_CONFIG`.
- Produces: enabled custom radios `value="<slug>"`, JS config entries, generic account-card branch, `escapeHtml()` helper.

- [ ] **Step 1: Write the failing tests**

Append to `tests/manual_payments_test.php`: assert `topup.php` contains `manual_methods_load($pdo)`, `manual_method_allowed(`, `escapeHtml(`, `GHOSST_MANUAL_CONFIG[method]`, and a comment/condition tying custom methods to `$manualPaymentEnabled` (exact string: `manualPaymentEnabled &&`).

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/manual_payments_test.php`
Expected: FAIL on the topup.php assertions.

- [ ] **Step 3: Render and wire custom methods**

After loading settings, build `$customMethods = array_values(array_filter($methods, fn ($m) => $manualPaymentEnabled && $m['enabled']))`; include them in `$anyMethodAvailable` and in the `$defaultMethod` fallback after PayPal. Render one `.method.nx-manual-method` radio per method (`data-is-auto="0"`, `data-currency="PHP"`, `bi-wallet2` icon, name label, note/number subtitle). Add each `{number, name, note}` to `GHOSST_MANUAL_CONFIG`. Add `escapeHtml()` and a generic `else if (GHOSST_MANUAL_CONFIG[method])` branch in `onMethodChange()` that renders name, note, number, and a `data-copy="${escapeHtml(cfg.number)}"` copy button; use the configured name in `updateSummaryQuotes()`.

- [ ] **Step 4: Run it to verify it passes**

Run: `php tests/manual_payments_test.php` then `php -l ghosst-web/topup.php`
Expected: PASS and no syntax errors.

- [ ] **Step 5: Verify, do not commit**

No tracked files changed.

---

### Task 4: Receipt validation + admin labels

**Files:**
- Modify: `ghosst-web/upload_receipt.php` (settings load ~24–34, allowlist ~49–68)
- Modify: `ghosst-web/admin/dashboard.php` (summary ~323–345, pending row ~1167–1171, processed row ~1225–1227)

**Interfaces:**
- Consumes: `manual_methods_load()`, `manual_method_allowed()`, `manual_method_label()`.
- Produces: dynamic manual allowlist; friendly labels/icons; summary labels "Manual Approved"/"Manual Rejected".

- [ ] **Step 1: Write the failing tests**

Append to `tests/manual_payments_test.php`: assert `upload_receipt.php` contains `manual_methods_load($pdo)` and `manual_method_allowed(`, and that it no longer contains the literal `$validMethods  = ['gcash', 'paypal'];` line; assert `dashboard.php` contains `manual_method_label(` and `Manual Approved`.

- [ ] **Step 2: Run it to verify it fails**

Run: `php tests/manual_payments_test.php`
Expected: FAIL on the integration assertions.

- [ ] **Step 3: Implement validation and labels**

In `upload_receipt.php`, keep the master-switch check first, then build the allowlist as `['gcash','paypal']` plus enabled custom keys via `manual_method_allowed()`; reject unknown/disabled keys with the existing "Invalid payment method selected." message. Keep GCash/PayPal individual disabled checks. In `dashboard.php`, load methods once, use `manual_method_label()` for pending/processed method cells, choose icons `phone-fill`/`paypal`/`qr-code-scan`/`wallet2`, and relabel the two summary card labels to "Manual Approved"/"Manual Rejected" without changing the SQL.

- [ ] **Step 4: Run it to verify it passes**

Run: `php tests/manual_payments_test.php`, `php -l ghosst-web/upload_receipt.php`, `php -l ghosst-web/admin/dashboard.php`
Expected: PASS, no syntax errors.

- [ ] **Step 5: Final gates and rollout note**

Run all PHP self-checks from `ghosst-web/api` (`php tests/manual_payments_test.php`, `php tests/social_test.php`, `php tests/reel_notifications_test.php`). No Flutter gates needed (no Dart changes). Upload the four changed website files plus the new helper. Manual smoke test: admin add GoTyme → top-up shows it with copyable number → submit test receipt → approve from dashboard.
