# Profile Bio & Cover Photo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users edit a bio and upload a cover photo on their own profile, stored on the site's FTP host.

**Architecture:** Add two columns to `users` via a one-shot SQL migration, two small API endpoints (bio save + cover upload), expose both fields in the allowlisted public profile payload, and add an Edit profile sheet to `ProfileHubScreen`. Reuse the existing FTP upload validator and `PUBLIC_CDN` URL pattern.

**Tech Stack:** PHP 8/PDO, Flutter/Dart with Dio + `file_picker`, plain PHP test scripts, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-26-profile-bio-cover-design.md`

## Global Constraints

- Bio: plain text, 0..300 chars, no HTML tags; empty clears it.
- Cover: JPG/PNG/WebP, max 5MB, stored in `uploads/covers/`, returned as relative path + absolute URL.
- API reads must work before the migration runs (`social_column_exists()` guard).
- User runs the SQL migration on Hostinger and uploads changed PHP files.
- `flutter run` is never used for verification; use `flutter analyze` and `flutter test`.
- Do not bump the build number or push to `main`.

## Review Focus

1. Pre-migration profile reads must not fatal → guard `bio`/`coverUrl` with `social_column_exists()`.
2. Bio must reject HTML and overlong text → pure validator with tests.
3. Cover upload must reject wrong types/oversized files and never write outside `uploads/covers/` → validator + path guard.
4. Old public payloads without bio/cover must still parse → defensive Dart parsing.
5. Profile edit UI must keep Share and overflow reachable → keyed Edit action tested alongside them.

---

### Task 1: Migration and API

**Files:**
- Create: `ghosst-web/database/mobile_app_profile_fields.sql`
- Modify: `ghosst-web/includes/image_upload.php`
- Modify: `ghosst-web/api/lib/social.php`
- Modify: `ghosst-web/api/routes/users.php`
- Modify: `ghosst-web/api/routes/uploads.php`
- Modify: `ghosst-web/api/index.php`
- Test: `ghosst-web/api/tests/upload_test.php`

**Interfaces:**
- Produces: `profile_bio_validate(string $bio): ?string`, `uploadCoverImage(string $field, string $slug): ?string`, `users_update_bio(array $ctx): array`, `uploads_cover_image(array $ctx): array`.
- Consumes: `social_column_exists()`, `require_user()`, `read_json()`, `header_value()`, `PUBLIC_CDN`.

- [ ] **Step 1: Write failing PHP tests**

In `upload_test.php`, assert `profile_bio_validate('Hi')` is null, overlong/HTML strings return an error, and `cover_image_url('uploads/covers/a.jpg')` equals `PUBLIC_CDN . '/uploads/covers/a.jpg'`.

- [ ] **Step 2: Run and confirm failure**

Run: `php ghosst-web/api/tests/upload_test.php`
Expected: FAIL because helpers do not exist.

- [ ] **Step 3: Implement migration + helpers + routes**

Write the guarded `ALTER TABLE users ADD COLUMN bio ... ADD COLUMN cover_url ...` migration. Add `uploadCoverImage()` to `includes/image_upload.php` (same MIME/size rules, `uploads/covers/`). Add `profile_bio_validate()` and `cover_image_url()` in `api/lib/uploads.php`. Add `users_update_bio()` in `routes/users.php` (auth required, JSON `{bio}`, returns `{ok,bio}`). Add `uploads_cover_image()` in `routes/uploads.php` (multipart `image`, returns `{ok,path,url}`). Register `POST /v1/me/profile` → `users_update_bio` and `POST /v1/uploads/cover` → `uploads_cover_image` in `index.php`. Extend `social_public_user()` with guarded `bio`/`coverUrl`.

- [ ] **Step 4: Run tests and lint**

Run: `php ghosst-web/api/tests/upload_test.php` and `php -l` on each changed PHP file.
Expected: pass; no syntax errors.

- [ ] **Step 5: Commit**

```bash
git add -f ghosst-web/database/mobile_app_profile_fields.sql ghosst-web/includes/image_upload.php ghosst-web/api && git commit -m "feat(api): editable bio and FTP cover upload"
```

### Task 2: Backend client and model

**Files:**
- Modify: `lib/services/models.dart`
- Modify: `lib/services/worker_backend.dart`
- Test: `test/social_models_test.dart`

**Interfaces:**
- Produces: `PublicUser.bio` (String, default ''), `PublicUser.coverUrl` (String?), `Backend.updateBio(String bio) → Future<String>`, `Backend.uploadCover(String path) → Future<String>` (absolute URL).
- Consumes: existing `ApiClient.post`, `FormData`/`MultipartFile`.

- [ ] **Step 1: Write failing tests**

In `test/social_models_test.dart`, add a `PublicUser.fromJson` case with `bio`/`coverUrl` and one without, asserting `''` and `null` defaults.

- [ ] **Step 2: Run and confirm failure**

Run: `flutter test test/social_models_test.dart --plain-name "bio"`
Expected: FAIL because the fields are absent.

- [ ] **Step 3: Implement**

Add the fields and defensive parsing. Add `Backend.updateBio` posting `{bio: bio.trim()}` to `/me/profile`. Add `Backend.uploadCover` posting `FormData` to `/uploads/cover`, returning `url` with `path` fallback.

- [ ] **Step 4: Run tests**

Run: `flutter test test/social_models_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/models.dart lib/services/worker_backend.dart test/social_models_test.dart
git commit -m "feat: profile bio and cover client methods"
```

### Task 3: Profile UI and docs

**Files:**
- Modify: `lib/screens/profile_hub_screen.dart`
- Modify: `lib/screens/user_profile_screen.dart`
- Modify: `test/profile_hub_screen_test.dart`
- Modify: `AGENTS.md`, `SETUP.md`

**Interfaces:**
- Consumes: `PublicUser.bio`/`coverUrl`, `Backend.updateBio`, `Backend.uploadCover`, existing `AppMenuButton`.
- Produces: keyed `profile-cover-band`, `profile-bio`, `profile-edit` action, and an edit sheet with `profile-bio-field`, `profile-cover-pick`, `profile-save`.

- [ ] **Step 1: Write failing widget tests**

Add: own profile shows cover image when `coverUrl` is set and black band otherwise; shows loaded bio; tapping `profile-edit` opens a sheet; changing bio + tapping `profile-save` calls the injected save callback. Keep Share and `profile-menu` assertions.

- [ ] **Step 2: Run and confirm failure**

Run: `flutter test test/profile_hub_screen_test.dart --plain-name "edit"`
Expected: FAIL because the action/sheet do not exist.

- [ ] **Step 3: Implement the UI**

Render `coverUrl` in `_header` (fallback black), show `user.bio` with the static tagline fallback, add a keyed Edit action, and build a modal sheet with bio `TextField` (max 300), cover picker, and Save. Inject `onSaveBio`/`onPickCover` for tests. Show loaded bio on public profiles too.

- [ ] **Step 4: Run tests and analyzer**

Run: `flutter test` then `flutter analyze`.
Expected: all tests pass; no new analyzer errors.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/profile_hub_screen.dart lib/screens/user_profile_screen.dart test/profile_hub_screen_test.dart AGENTS.md SETUP.md
git commit -m "feat(ui): edit profile bio and cover"
```
