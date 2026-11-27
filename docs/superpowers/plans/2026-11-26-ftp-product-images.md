# Product Images: Cloudinary → FTP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Cloudinary product-image uploads with the site's existing FTP storage, exposed through an admin-only API endpoint.

**Architecture:** The website already stores product images in `uploads/products/` via `includes/image_upload.php`. Add a PHP API route that calls that helper for the app admin, reuses `PUBLIC_CDN` for display URLs, and deletes local files on product deletion. On Flutter, delete the Cloudinary service and call the new endpoint from the admin screen.

**Tech Stack:** PHP 8/PDO, Flutter/Dart with the existing Dio `ApiClient`, plain PHP test scripts.

**Spec:** `docs/superpowers/specs/2026-11-26-ftp-product-images-design.md`

## Global Constraints

- JPG/PNG/WebP only, max 5MB (same rules as `includes/image_upload.php`).
- Upload route is admin-only via `require_admin($ctx)`.
- `PUBLIC_CDN` stays as the public base URL; relative keys become absolute in `to_product()`.
- No new host or signed tickets; do not touch Reels media hosting.
- `flutter run` is never used for verification; use `flutter analyze` and `flutter test`.
- Do not bump the build number or push to `main`.

## Review Focus

1. Non-admin must not be able to upload → add an API test asserting `require_admin` rejection.
2. Missing/invalid file must give a clean 400, not a PHP fatal → test empty `$_FILES`.
3. Product delete must only remove files inside `uploads/products/` → test that a foreign path is rejected.
4. Old Cloudinary URLs must not break product listing → `to_product()` passes absolute URLs through unchanged (existing behavior).
5. Admin screen must stop talking to Cloudinary → assert no import/call remains after the change.

---

### Task 1: Admin product-image upload endpoint

**Files:**
- Modify: `ghosst-web/api/routes/uploads.php`
- Modify: `ghosst-web/api/index.php` (register route)
- Test: `ghosst-web/api/tests/upload_test.php` (new)

**Interfaces:**
- Produces: `uploads_product_image(array $ctx): array` returning `{ok:true, path:'uploads/products/<name>.<ext>'}`; throws `ApiError(400, 'image_required')` for no file and `ApiError(400, 'invalid_image')` for validation failures.
- Consumes: `uploadProductImage(string $field, string $slug): ?string` from `ghosst-web/includes/image_upload.php`.

- [ ] **Step 1: Write the failing PHP test**

Create `ghosst-web/api/tests/upload_test.php` following `social_test.php` conventions. Assert `uploads_product_image(['user' => ['id' => 1, 'is_admin' => true]])` with empty `$_FILES` raises `ApiError` with status 400 and code `image_required`, and that a non-admin context is rejected before any file work.

- [ ] **Step 2: Run it and confirm it fails**

Run: `php ghosst-web/api/tests/upload_test.php`
Expected: FAIL because the function does not exist.

- [ ] **Step 3: Implement the route**

In `routes/uploads.php`, require `__DIR__ . '/../../includes/image_upload.php'`, call `require_admin($ctx)`, validate `$_FILES['image']`, call `uploadProductImage('image', 'product')`, map `RuntimeException` to `ApiError(400, 'invalid_image', $e->getMessage())`, and return `['ok' => true, 'path' => $path]`. Register `POST /v1/uploads/product-image` → `uploads_product_image` in `index.php` near the existing upload routes.

- [ ] **Step 4: Run the test and lint**

Run: `php ghosst-web/api/tests/upload_test.php` then `php -l ghosst-web/api/routes/uploads.php`
Expected: tests pass; lint clean.

- [ ] **Step 5: Commit**

```bash
git add -f ghosst-web/api/routes/uploads.php ghosst-web/api/index.php ghosst-web/api/tests/upload_test.php
git commit -m "feat(api): admin FTP product-image upload"
```

### Task 2: Delete local files and remove Cloudinary from the API

**Files:**
- Create: `ghosst-web/api/lib/uploads.php`
- Modify: `ghosst-web/api/routes/products.php:227-237`
- Modify: `ghosst-web/api/config.php:46-49`
- Modify: `ghosst-web/api/index.php:21`
- Delete: `ghosst-web/api/lib/cloudinary.php`
- Test: `ghosst-web/api/tests/upload_test.php`

**Interfaces:**
- Produces: `delete_stored_image(string $key): bool` — true only for a real file under `uploads/products/`; false otherwise.
- Consumes: `discard_images(array $keys): int` in `routes/products.php`.

- [ ] **Step 1: Write the failing test**

In `upload_test.php`, assert `delete_stored_image('https://res.cloudinary.com/...')` is false and `delete_stored_image('../config.php')` is false — no real files needed.

- [ ] **Step 2: Run it and confirm it fails**

Run: `php ghosst-web/api/tests/upload_test.php`
Expected: FAIL because the function is absent.

- [ ] **Step 3: Implement and remove Cloudinary**

Add `delete_stored_image()` in `lib/uploads.php` using `realpath` containment under `uploads/products`. Change `discard_images()` to call it for every key instead of `destroy_image()`. Remove the `require` of `lib/cloudinary.php`, the `CLOUDINARY_*` defines, and delete `lib/cloudinary.php`. Keep `PUBLIC_CDN`.

- [ ] **Step 4: Run the test and lint**

Run: `php ghosst-web/api/tests/upload_test.php` and `php -l` on each changed PHP file.
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add -f ghosst-web/api && git commit -m "refactor(api): drop Cloudinary, delete local product images"
```

### Task 3: Flutter uploader and docs

**Files:**
- Delete: `lib/services/cloudinary.dart`
- Modify: `lib/services/worker_backend.dart` (add `uploadProductImage`)
- Modify: `lib/screens/admin_screen.dart:558-581`
- Modify: `test/services_misc_test.dart` (remove Cloudinary group)
- Modify: `AGENTS.md`, `SETUP.md`, `PERF.md`

**Interfaces:**
- Produces: `Backend.uploadProductImage(String path) → Future<String>` returning the relative `uploads/products/...` path; throws `ApiException` on failure.
- Consumes: existing `ApiClient.post` with `FormData` and injected `loadProducts`/`loadClaims` in admin tests.

- [ ] **Step 1: Write the failing test**

Add a test in `test/services_misc_test.dart` asserting `Backend` has no Cloudinary symbols (compile-time via removing the import) and add a widget test in `test/admin_screens_test.dart` that pumps `AdminScreen` and asserts it no longer references Cloudinary. Keep it small.

- [ ] **Step 2: Run it and confirm it fails**

Run: `flutter test test/services_misc_test.dart test/admin_screens_test.dart`
Expected: FAIL while the Cloudinary import/service still exists.

- [ ] **Step 3: Implement**

Delete `lib/services/cloudinary.dart`. Add `Backend.uploadProductImage` posting `FormData.fromMap({'image': MultipartFile.fromFileSync(path)})` to `/uploads/product-image` and returning `res['path'] as String`. Change `_pickImages` to call it and collect the returned paths. Remove Cloudinary references from AGENTS.md, SETUP.md, and PERF.md; describe FTP product images instead.

- [ ] **Step 4: Run tests and analyzer**

Run: `flutter test` then `flutter analyze`.
Expected: all tests pass; no new analyzer errors.

- [ ] **Step 5: Commit**

```bash
git add -A lib test AGENTS.md SETUP.md PERF.md docs/superpowers/specs/2026-11-26-ftp-product-images-design.md
git commit -m "refactor: use FTP for product images instead of Cloudinary"
```
