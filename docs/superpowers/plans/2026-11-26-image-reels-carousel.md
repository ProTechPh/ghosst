# Image-only Reels Carousel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace MP4-only Reels with public image posts containing 1–5 ordered images uploaded to z.com, displayed as a horizontal carousel inside the existing vertical feed.

**Architecture:** The PHP API creates one pending reel plus `app_reel_media` rows and returns one short-lived HS256 ticket per image. The app uploads each image directly to a small z.com PHP endpoint, then completes the post through the main API. MySQL stores post/media metadata and existing social rows; z.com stores public image files. Flutter renders a vertical post `PageView` and a nested horizontal image `PageView` with dots.

**Tech Stack:** Flutter/Dart (`file_picker`, `dio`, `crypto`, `cached_network_image`), PHP 8/PDO MySQL, z.com PHP image host, existing website admin.

**Spec:** `docs/superpowers/specs/2026-11-26-image-reels-carousel-design.md` (2026-11-26). Supersedes video upload/playback sections of `docs/superpowers/specs/2026-11-25-social-features-design.md` and `docs/superpowers/plans/2026-11-25-reels.md`.

## Global Constraints

- 1–5 images per post; allowed MIME/types: `image/jpeg` (`.jpg/.jpeg`), `image/png` (`.png`), `image/webp` (`.webp`).
- 10 MB per image, 50 MB total per post. Caption max 300 UTF-8 chars. Max 5 posts per rolling 24 hours per user.
- No signing secret in the APK. Upload tickets expire in 15 minutes and are bound to `sub`, `reelId`, `position`, `purpose=reel-image-upload`, `sha256`, `sizeBytes`, `mimeType`, `ext`.
- The main API never proxies image bytes. The app never sends API JWT to z.com.
- Feed queries only return visible reels that have at least one visible `app_reel_media` row; legacy video-only rows stay hidden.
- Keep existing likes/comments/follows/reports/moderation/account deletion behavior.
- Backend files live in the canonical gitignored tree `D:\key-mobile\ghosst\ghosst-web\...` (repo has `ghosst-web/` junction). Flutter repo commits contain app/docs/rules/tests only; do not commit backend secrets/config.
- Do not manually bump build number. Do not push/merge/deploy without explicit owner approval.

## Review Focus

1. Wrong ticket purpose/expiry/signature, hash/size/MIME/extension mismatch, or path traversal must be rejected before publish.
2. Replayed init/complete/upload must be idempotent; same idempotency key with different payload must return conflict.
3. Old video-only reels must not crash or appear in the image feed/profile grid.
4. Owner/admin deletion and account deletion must remove `app_reel_media` metadata and best-effort delete deterministic z.com files.
5. Carousel UI must not reintroduce video playback, must preserve order, and must keep only current-page behavior simple.

---

### Task 1: DB migration and Flutter reel models

**Files:**
- Create: `D:\key-mobile\ghosst\ghosst-web\database\mobile_app_reel_images.sql`
- Modify: `D:\key-mobile\ghosst\ghosst-web\database\mobile_app_social.sql` (append/create compatible image table block or document follow-up migration; prefer additive rerunnable migration file)
- Modify: `lib/services/models.dart`
- Modify: `test/social_models_test.dart`
- Modify: `test/reels_screen_test.dart`
- Modify: `test/user_profile_screen_test.dart`

**Interfaces:**
- Produces:
  - `class ReelImage { int position; String url, sha256, mimeType; int sizeBytes; int? width, height; factory ReelImage.fromJson(...); }`
  - `Reel` gains `List<ReelImage> images`; keeps `posterUrl`/caption/creator/counts/flags. `videoUrl` and `durationMs` removed from image-only model.
  - `class ReelUploadImage { String fileName, sha256, mimeType; int sizeBytes; }`
  - `class ReelUploadTicket { String reelId; DateTime expiresAt; List<ReelImageUploadTicket> uploads; }`
  - `class ReelImageUploadTicket { int position; String uploadUrl, token, sha256, storageKey; int maxBytes; }`

- [ ] **Step 1: Write failing model tests**

In `test/social_models_test.dart`, replace video expectations with carousel expectations:

```dart
test('Reel parses ordered images and poster', () {
  final reel = Reel.fromJson({
    'id': 'r1',
    'caption': 'Hello',
    'posterUrl': 'https://video.example/media/r1-1.jpg',
    'images': [
      {'position': 2, 'url': 'https://video.example/media/r1-2.jpg', 'sha256': 'b'*64, 'sizeBytes': 20, 'mimeType': 'image/png'},
      {'position': 1, 'url': 'https://video.example/media/r1-1.jpg', 'sha256': 'a'*64, 'sizeBytes': 10, 'mimeType': 'image/jpeg'},
    ],
    'createdAt': '2026-01-01T00:00:00.000Z',
    'creator': {'id': 42, 'displayName': 'Jeric'},
  });
  expect(reel.images.map((i) => i.position), [1, 2]);
  expect(reel.posterUrl, 'https://video.example/media/r1-1.jpg');
});

test('ReelUploadTicket parses per-image tickets', () {
  final ticket = ReelUploadTicket.fromJson({
    'reel': {'id': 'r1', 'status': 'pending'},
    'uploads': [
      {'position': 1, 'url': 'https://z/upload.php', 'token': 't1', 'expiresAt': '2026-01-01T00:15:00.000Z', 'maxBytes': 10485760, 'sha256': 'a'*64, 'storageKey': 'r1-1.jpg'}
    ],
  });
  expect(ticket.reelId, 'r1');
  expect(ticket.uploads.single.position, 1);
});
```

Update `test/reels_screen_test.dart` and `test/user_profile_screen_test.dart` helpers to construct `Reel(images: [...])`.

Run: `flutter test test/social_models_test.dart test/reels_screen_test.dart test/user_profile_screen_test.dart`
Expected: FAIL because `ReelImage`, `images`, and new ticket shape do not exist.

- [ ] **Step 2: Add rerunnable DB migration**

Create `D:\key-mobile\ghosst\ghosst-web\database\mobile_app_reel_images.sql`:

```sql
CREATE TABLE IF NOT EXISTS app_reel_media (
    reel_id    CHAR(36) NOT NULL,
    position   TINYINT UNSIGNED NOT NULL,
    image_url  VARCHAR(1000) NULL,
    storage_key VARCHAR(255) NOT NULL,
    sha256     CHAR(64) NOT NULL,
    size_bytes INT UNSIGNED NOT NULL,
    mime_type  VARCHAR(50) NOT NULL,
    width      INT UNSIGNED NULL,
    height     INT UNSIGNED NULL,
    status     ENUM('pending','visible','deleted') NOT NULL DEFAULT 'pending',
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    PRIMARY KEY (reel_id, position),
    UNIQUE KEY uq_reel_media_storage (storage_key),
    KEY idx_reel_media_reel_status (reel_id, status, position)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

Keep `app_reels` table intact for compatibility; old video columns remain unused.

- [ ] **Step 3: Implement Dart models**

In `lib/services/models.dart`, add `ReelImage`; update `Reel.fromJson` to parse `images`, sort by position, default `posterUrl` to first image URL when absent. Update `ReelUploadTicket` to parse `uploads` list and optional shared `expiresAt`. Keep parsing tolerant of missing/invalid entries.

- [ ] **Step 4: Run tests**

Run: `flutter test test/social_models_test.dart`
Expected: PASS for model tests; other reel tests may still fail until UI/client updated.

- [ ] **Step 5: Commit**

```bash
git add lib/services/models.dart test/social_models_test.dart test/reels_screen_test.dart test/user_profile_screen_test.dart docs/superpowers/specs/2026-11-26-image-reels-carousel-design.md docs/superpowers/plans/2026-11-26-image-reels-carousel.md
git commit -m "feat(reels): add carousel image models and migration plan"
```

### Task 2: z.com image hosting endpoint

**Files:**
- Modify: `D:\key-mobile\ghosst\ghosst-web\reels\lib.php`
- Modify: `D:\key-mobile\ghosst\ghosst-web\reels\upload.php`
- Modify: `D:\key-mobile\ghosst\ghosst-web\reels\delete.php`
- Modify: `D:\key-mobile\ghosst\ghosst-web\reels\media\.htaccess`
- Modify: `D:\key-mobile\ghosst\ghosst-web\reels\README.md`
- Modify: `D:\key-mobile\ghosst\ghosst-web\reels\tests\upload_test.php`

**Interfaces:**
- Produces:
  - `reel_hosting_verify_ticket(..., 'reel-image-upload')` accepts claims: `reelId`, `position` 1..5, `sha256`, `sizeBytes` 1..10485760, `mimeType`, `ext`.
  - `reel_hosting_media_name(string $reelId, int $position, string $ext): string`
  - `reel_hosting_public_media_url(string $reelId, int $position, string $ext): string`
  - `reel_hosting_image_magic(string $path, string $mime): bool`
  - Upload response: `{ok,imageUrl,sha256,sizeBytes,width,height}`

- [ ] **Step 1: Write failing PHP host tests**

Extend `ghosst-web/reels/tests/upload_test.php` with cases:

```php
$imgClaims = ['sub'=>'42','reelId'=>$uuid,'position'=>1,'purpose'=>'reel-image-upload','sha256'=>str_repeat('a',64),'sizeBytes'=>123,'mimeType'=>'image/jpeg','ext'=>'jpg','jti'=>'t','iat'=>time(),'exp'=>time()+900];
// build token helper and assert verify passes
check(reel_hosting_media_name($uuid, 1, 'jpg') === $uuid . '-1.jpg', 'image filename accepted');
check(reel_hosting_media_name($uuid, 6, 'jpg') === '', 'bad position rejected');
check(reel_hosting_media_name('../bad', 1, 'jpg') === '', 'path traversal rejected');
```

Add temp-file magic-byte checks for JPEG/PNG/WebP and reject bad bytes.

Run: `php ghosst-web/reels/tests/upload_test.php`
Expected: FAIL because image helpers are missing.

- [ ] **Step 2: Implement host helpers**

In `reels/lib.php`, add allowlists:

```php
function reel_hosting_allowed_image(string $mime, string $ext): bool {
  return in_array([$mime, $ext], [['image/jpeg','jpg'],['image/jpeg','jpeg'],['image/png','png'],['image/webp','webp']], true);
}
```

Verify ticket includes `position` int 1..5 and allowed mime/ext. Keep existing MP4 delete compatibility by allowing delete helper to remove legacy `<id>.mp4` and image variants.

- [ ] **Step 3: Implement image upload handler**

In `reels/upload.php`, branch by ticket purpose:
- `reel-image-upload`: require multipart `image`, max 10 MB, `finfo` MIME allowlist, magic bytes, SHA-256 match, deterministic `<reelId>-<position>.<ext>` with exclusive create; replay identical returns existing URL+dimensions; mismatch returns 409. Use `getimagesize()` for width/height when available.
- Keep `reel-upload` MP4 path temporarily for legacy cleanup/testing only if needed; otherwise return 410/400 with clear message. Prefer removing MP4 upload acceptance after app migration; document in README.

- [ ] **Step 4: Harden delete and media serving**

In `reels/delete.php`, decode manifest before validating bound ticket. Accept up to 100 reel IDs and delete `<id>.mp4` plus `<id>-1..5.{jpg,jpeg,png,webp}` only inside media root. In `.htaccess`, allow jpg/jpeg/png/webp with nosniff and deny scripts.

- [ ] **Step 5: Run PHP tests**

Run: `php ghosst-web/reels/tests/upload_test.php`
Expected: PASS.

- [ ] **Step 6: Commit (backend tree note)**

Backend files are in canonical gitignored tree; do not commit from Flutter repo. Record in plan execution notes. If the backend tree is its own git repo, commit there separately with owner approval.

### Task 3: PHP API upload lifecycle for image carousels

**Files:**
- Modify: `D:\key-mobile\ghosst\ghosst-web\api\config.php` (keep existing secret/URLs; no new secret)
- Modify: `D:\key-mobile\ghosst\ghosst-web\api\lib\reels.php`
- Modify: `D:\key-mobile\ghosst\ghosst-web\api\routes\reels.php`
- Modify: `D:\key-mobile\ghosst\ghosst-web\api\lib\idempotency.php` (only if needed; already supports request hash)
- Modify: `D:\key-mobile\ghosst\ghosst-web\api\cleanup_social.php`
- Modify: `D:\key-mobile\ghosst\ghosst-web\api\tests\social_test.php`

**Interfaces:**
- Produces:
  - `reels_upload_init` accepts `{caption, images:[{fileName,sizeBytes,mimeType,sha256}]}` and returns `{ok,reel:{id,status},uploads:[...]}`.
  - `reels_upload_complete` accepts `{images:[{position,imageUrl,sha256,sizeBytes}]}` and marks post/media visible atomically.
  - `reel_media_public_url(string $reelId, int $position, string $ext): string`
  - `reels_delete_files` deletes image variants and legacy mp4.

- [ ] **Step 1: Write failing API tests**

In `ghosst-web/api/tests/social_test.php`, add cases:

```php
check(reel_ticket_verify(reel_ticket_sign([
  'sub'=>'42','reelId'=>'r1','position'=>1,'purpose'=>'reel-image-upload','sha256'=>str_repeat('a',64),'sizeBytes'=>123,'mimeType'=>'image/jpeg','ext'=>'jpg'
]), 'reel-image-upload') !== null, 'image ticket verifies');
```

Add validation helpers/tests for image allowlist, total size, 1..5 count, and completion payload mismatch. Update existing reel completion tests to image payload shape.

Run: `php ghosst-web/api/tests/social_test.php`
Expected: FAIL.

- [ ] **Step 2: Implement init**

In `routes/reels.php`:
- Require `Idempotency-Key`.
- Validate caption and image array count 1..5.
- Validate each image: mime/ext allowlist, size 1..10485760, SHA-256, total <= 52428800.
- Lock user row, enforce 5 posts / rolling 24h by `app_reels` rows with status != deleted.
- Insert `app_reels` pending row; insert `app_reel_media` pending rows with deterministic `storage_key` `<reelId>-<position>.<ext>`.
- Store idempotent response without tickets; on replay, regenerate fresh tickets for same pending rows.
- Return per-image tickets with `purpose=reel-image-upload` and claims including position/ext/mime.

- [ ] **Step 3: Implement complete**

- Require `Idempotency-Key` and exact image set by position.
- Lock reel row and media rows.
- Verify owner, pending state, every position present once, URL equals expected deterministic URL, sha256/size match row.
- In transaction: mark media visible, set `app_reels.status='visible'`, set `poster_url` to first image URL, update timestamps.
- Replay same payload after visible returns success; different payload returns 409.

- [ ] **Step 4: Update cleanup/delete helpers**

In `api/lib/reels.php`, make `reels_delete_files` request z.com deletion for legacy mp4 and all image variants; bind ticket to reel manifest as before. In `cleanup_social.php`, when expiring pending reels also delete `app_reel_media` rows and call delete files.

- [ ] **Step 5: Run PHP tests**

Run: `php ghosst-web/api/tests/social_test.php`
Expected: PASS.

### Task 4: Feed/social/admin API shape for images

**Files:**
- Modify: `D:\key-mobile\ghosst\ghosst-web\api\routes\reel_social.php`
- Modify: `D:\key-mobile\ghosst\ghosst-web\api\routes\users.php`
- Modify: `D:\key-mobile\ghosst\ghosst-web\api\routes\admin_reels.php`
- Modify: `D:\key-mobile\ghosst\ghosst-web\api\routes\account.php`
- Modify: `D:\key-mobile\ghosst\ghosst-web\api\lib\social.php`
- Modify: `D:\key-mobile\ghosst\ghosst-web\admin\reels.php`
- Modify: `D:\key-mobile\ghosst\ghosst-web\api\tests\social_test.php`

**Interfaces:**
- Produces:
  - Reel payload: `{id,caption,posterUrl,images:[{position,url,width,height}],createdAt,creator,likeCount,commentCount,isLiked,isFollowing,isMine}`
  - Feed/profile queries require visible media: `EXISTS (SELECT 1 FROM app_reel_media m WHERE m.reel_id=r.id AND m.status='visible')`.

- [ ] **Step 1: Write failing API shape tests**

Add assertions that feed/profile map `images` and omit `videoUrl/durationMs`, and that creator reel query joins/requires visible media. Add account deletion test expecting `DELETE FROM app_reel_media` before/with reel cleanup.

Run: `php ghosst-web/api/tests/social_test.php`
Expected: FAIL.

- [ ] **Step 2: Implement feed/profile mapping**

Update `reel_social_map`, `users_reels`, and any reel detail query to include ordered visible images. Use one grouped query or a second query by reel IDs; keep pagination deterministic. Filter out reels without visible media.

- [ ] **Step 3: Update admin/moderation**

In `api/routes/admin_reels.php` and `admin/reels.php`, show poster/first image thumbnail and image count; remove `<video>` tag. Keep status actions and report queue behavior.

- [ ] **Step 4: Update account deletion**

In `routes/account.php`, delete `app_reel_media` rows for owned reels and reported/commented cleanup as needed before deleting `app_reels`. Keep best-effort file deletion after commit.

- [ ] **Step 5: Run PHP tests**

Run: `php ghosst-web/api/tests/social_test.php`
Expected: PASS.

### Task 5: Flutter upload service and backend client

**Files:**
- Modify: `lib/services/reel_upload_service.dart`
- Modify: `lib/services/worker_backend.dart`
- Modify: `test/reel_upload_test.dart`

**Interfaces:**
- Produces:
  - `ReelUploadDraft {caption, images:[ReelDraftImage{path,fileName,sizeBytes,sha256,mimeType}], idempotencyBase}`
  - `ReelUploadService.validateImages(...)`
  - `ReelUploadService.uploadImages({required List<ReelDraftImage> images, required ReelUploadTicket ticket, void Function(int done,int total)? onImageProgress})`
  - `Backend.startReelUpload({required String caption, required List<Map<String,dynamic>> images, required String idempotencyKey})`
  - `Backend.completeReelUpload({required String reelId, required List<Map<String,dynamic>> images, required String idempotencyKey})`

- [ ] **Step 1: Write failing Flutter tests**

Update `test/reel_upload_test.dart`:

```dart
test('upload guard rejects bad image count/type/size/hash', () { ... });
test('ReelUploadDraft keeps stable base key across caption change', () { ... });
```

Add a test that upload service rejects ticket/image count mismatch and expired ticket before network. Keep SHA-256 helper test.

Run: `flutter test test/reel_upload_test.dart`
Expected: FAIL.

- [ ] **Step 2: Implement upload service**

In `reel_upload_service.dart`:
- Replace MP4-only constants with image allowlist: jpg/jpeg/png/webp, 10 MB each, 50 MB total, 1..5 images.
- Compute SHA-256 per file.
- Upload sequentially by ticket position; field name `image`. Return per-image results with `imageUrl, sha256, sizeBytes, width, height`.
- Do not send API auth header to z.com.

- [ ] **Step 3: Implement backend client**

In `worker_backend.dart`:
- `startReelUpload` posts `caption` and `images` metadata; idempotency key `<base>-init`.
- `completeReelUpload` posts image completion payload; idempotency key `<base>-complete`.
- Parse `ReelUploadTicket.uploads`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/reel_upload_test.dart test/social_models_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/reel_upload_service.dart lib/services/worker_backend.dart test/reel_upload_test.dart
git commit -m "feat(reels): upload image carousel tickets"
```

### Task 6: Flutter upload UI

**Files:**
- Modify: `lib/screens/reel_upload_screen.dart`
- Modify: `lib/main.dart`
- Modify: `test/reel_upload_test.dart`

**Interfaces:**
- Produces:
  - Multi-image picker (`FileType.image`, `allowMultiple: true`, max 5).
  - Draft shows selected image names/count and per-image/overall progress.
  - Submit calls prepare -> upload images sequentially -> complete.

- [ ] **Step 1: Write failing widget tests**

Add tests for: rejects 0 or >5 selected images, rejects unsupported type/oversized image, successful multi-image submit calls prepare/submit once with ordered images, and caption edit keeps idempotency base.

Run: `flutter test test/reel_upload_test.dart`
Expected: FAIL.

- [ ] **Step 2: Implement upload screen**

Replace single MP4 picker with multi-image picker. Keep caption. Disable picker while uploading. Show simple progress: “Uploading 2/5”. On error, keep draft/ticket for retry when safe.

- [ ] **Step 3: Wire main**

In `main.dart`, build draft images metadata, call `Backend.startReelUpload`, upload via `ReelUploadService`, then `Backend.completeReelUpload` with returned image URLs/hashes/sizes.

- [ ] **Step 4: Run tests**

Run: `flutter test test/reel_upload_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/reel_upload_screen.dart lib/main.dart test/reel_upload_test.dart
git commit -m "feat(reels): multi-image upload flow"
```

### Task 7: Flutter carousel feed and profile grid

**Files:**
- Modify: `lib/screens/reels_screen.dart`
- Modify: `lib/screens/user_profile_screen.dart`
- Modify: `lib/screens/reel_comments_screen.dart` (only if payload/type changes require)
- Modify: `lib/main.dart` (remove video-only wiring assumptions)
- Modify: `test/reels_screen_test.dart`
- Modify: `test/user_profile_screen_test.dart`
- Modify: `pubspec.yaml` (remove `video_player` if unused)

**Interfaces:**
- Produces:
  - `ReelsScreen` renders image carousel per reel: horizontal `PageView.builder`, dot indicator, `CachedNetworkImage`, error placeholder.
  - No `ReelPlayback`, no `video_player` import.
  - Profile reel grid uses `reel.posterUrl` (first image).

- [ ] **Step 1: Write failing widget tests**

Update `test/reels_screen_test.dart`:
- Remove playback/controller lifecycle expectations.
- Assert carousel renders dots/count for multiple images.
- Assert horizontal swipe changes image indicator/page.
- Keep like/comment/profile/report/delete/feed switching/empty/error/unconfigured behavior.

Update profile test to expect poster image rendering from carousel model.

Run: `flutter test test/reels_screen_test.dart test/user_profile_screen_test.dart`
Expected: FAIL.

- [ ] **Step 2: Implement carousel UI**

In `reels_screen.dart`, replace `_ReelPage` video/player logic with image carousel state (`_imageIndex`). Use `InteractiveViewer` only if already cheap; otherwise plain `CachedNetworkImage` with fit cover. Keep right action rail and bottom caption. Add small dot indicator.

- [ ] **Step 3: Remove video dependency/wiring**

Delete unused `video_player` import and dependency if no remaining references. Update `main.dart` upload wiring and any reel open code paths.

- [ ] **Step 4: Run tests**

Run: `flutter test test/reels_screen_test.dart test/user_profile_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/reels_screen.dart lib/screens/user_profile_screen.dart lib/main.dart pubspec.yaml pubspec.lock test/reels_screen_test.dart test/user_profile_screen_test.dart
git commit -m "feat(reels): render image carousels"
```

### Task 8: Docs, gates, and rollout notes

**Files:**
- Modify: `docs/superpowers/specs/2026-11-25-social-features-design.md` (mark reels section superseded by image carousel spec)
- Modify: `D:\key-mobile\ghosst\ghosst-web\reels\README.md`
- Modify: `D:\key-mobile\ghosst\ghosst-web\database/mobile_app_reel_images.sql` (final)
- Modify: `firestore.rules` only if needed (expected no change)

**Verification:**
- [ ] **Step 1: Run focused Flutter tests**

Run: `flutter test test/social_models_test.dart test/reel_upload_test.dart test/reels_screen_test.dart test/user_profile_screen_test.dart`
Expected: PASS.

- [ ] **Step 2: Run full Flutter gates**

Run: `flutter analyze`
Expected: no issues.

Run: `flutter test`
Expected: all pass.

- [ ] **Step 3: Run PHP checks**

Run: `php -l` on changed PHP files in `D:\key-mobile\ghosst\ghosst-web\api` and `D:\key-mobile\ghosst\ghosst-web\reels`.
Expected: no syntax errors.

Run: `php ghosst-web/api/tests/social_test.php` and `php ghosst-web/reels/tests/upload_test.php` from canonical tree.
Expected: `ok`.

- [ ] **Step 4: Manual smoke (owner device/staging)**

- Upload 1 image and 5 images; verify order, dots, swipe, feed/profile/moderation visibility.
- Retry a failed image upload; confirm no duplicate post.
- Confirm old video-only rows do not appear.
- Confirm delete removes post and files become unavailable.

- [ ] **Step 5: Final commit**

```bash
git add docs/superpowers/specs/2026-11-25-social-features-design.md docs/superpowers/specs/2026-11-26-image-reels-carousel-design.md docs/superpowers/plans/2026-11-26-image-reels-carousel.md
git commit -m "docs(reels): plan image-only carousel migration"
```

## Deployment Notes (owner-controlled)

1. Run `mobile_app_reel_images.sql` on production MySQL.
2. Deploy updated `ghosst-web/api/*` and `ghosst-web/reels/*` to matching HTTPS paths; keep existing `REEL_UPLOAD_SECRET`.
3. Verify z.com accepts jpg/png/webp and rejects invalid tickets/types/sizes.
4. Deploy website admin page if used.
5. Ship Flutter app after gates pass. Do not delete old media columns/files until image rollout is confirmed stable.
