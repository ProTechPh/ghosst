# Product Images: Cloudinary → FTP — Design

**Date:** 2026-11-26

## Intent

The Cloudinary cloud `zp6uwlrj` is disabled, so every product image URL returns
`401 cloud_name ... is disabled`. Remove Cloudinary from the app and API and use
the site's existing FTP storage (`uploads/products/`) for product images instead.

## Goals

- App admin can upload product images to the same FTP host the website already
  uses.
- Product deletion removes the stored FTP file as a best-effort cleanup.
- No Cloudinary code, config, or secrets remain in active app/API code.
- Existing app flows (product create/edit, image display) keep working.

## Non-goals

- No second z.com-style uploader with signed tickets — the FTP target already
  exists and the API already authenticates admins.
- **No migration of the old Cloudinary images.** They are on a disabled cloud;
  the admin must re-upload them. This change does not recover them.
- No changes to Reels media hosting (still z.com) or website admin pages.

## Constraints

- Reuse `ghosst-web/includes/image_upload.php` rules: JPG/PNG/WebP, max 5MB,
  sanitized slug, files land in `uploads/products/`.
- Upload endpoint must be admin-only and use the existing JWT auth.
- `PUBLIC_CDN` stays as the public base URL so relative keys become absolute
  image URLs in `to_product()` (`routes/products.php:20-23`).
- Tests use injected loaders/clients; no network or FTP access in `flutter test`.
- `flutter run` is never used for verification; use `flutter analyze` and
  `flutter test`.

## Approaches

- **A (picked):** add `POST /v1/uploads/product-image` to the PHP API, reusing
  `uploadProductImage()`; Flutter admin calls it instead of Cloudinary. Smallest
  change because the FTP storage and the upload validator already exist.
- **B (rejected):** build a separate z.com-style signed-ticket uploader like
  Reels. More moving parts and a second storage host to maintain.

## Decided how

1. **PHP API:** new route `POST /v1/uploads/product-image` (admin required) that
   validates `$_FILES['image']` through the existing helper, stores it under
   `uploads/products/`, and returns `{ok, path}` with the relative path.
2. **PHP API cleanup:** replace `destroy_image()` in `discard_images()`
   (`routes/products.php:228-237`) with deletion of local `uploads/products/`
   files; drop `api/lib/cloudinary.php`, its `index.php` require, and
   `CLOUDINARY_*` config defines. Keep `PUBLIC_CDN`.
3. **Flutter:** delete `lib/services/cloudinary.dart`; add
   `Backend.uploadProductImage(String path)` posting the file to the new
   endpoint with the existing auth client; change `admin_screen.dart:_pickImages`
   to use it and store the returned path.
4. **Tests:** remove Cloudinary assertions from `test/services_misc_test.dart`;
   add a focused test that the admin screen uses the backend uploader.
5. **Docs:** update AGENTS.md, SETUP.md, and PERF.md to describe FTP product
   images. Historical specs/plans are left untouched.

## Left to builder

- Decide the exact status/error mapping for oversized or wrong-type images
  (mirror the website helper's messages).
- Verify with `flutter analyze` and `flutter test`.
