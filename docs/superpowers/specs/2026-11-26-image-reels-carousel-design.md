# Image-only Reels Carousel — Design

## Intent

Replace the video-only Reels flow with public photo posts. A user may upload **1–5 images** in one post; viewers swipe the images horizontally inside the existing vertical Reels feed. The owner keeps media on **z.com** over HTTPS.

This design supersedes the video-upload and playback portions of `2026-11-25-social-features-design.md`. Chat, profiles, follows, likes, comments, reports, moderation, and account deletion remain.

## Goals

- Gallery picker accepts 1–5 JPG, JPEG, PNG, or WebP images.
- Each image is at most 10 MB; a post is at most 50 MB total.
- Signed, direct-to-z.com uploads; the app never holds the signing secret.
- Carousel preserves image order and shows a position indicator.
- Existing social interactions and moderation continue to work.
- Old video rows cannot break the image-only app.

## Non-goals

- Video upload, playback, camera recording, trimming, filters, or slideshow autoplay.
- Image editing, cropping, or client-side compression.
- Reel sharing, exact view counts, or pre-moderation.
- Deleting legacy video columns or files automatically.

## Constraints

- Flutter Android app; PHP 8 API; MySQL/MariaDB; z.com PHP host.
- Public media URLs are HTTPS.
- The main API never proxies image bytes.
- Reels remain unavailable when z.com config is blank.
- Backend files stay in the canonical gitignored `ghosst-web/` tree; Flutter commits contain app/docs/rules changes only.

## Approaches considered

### 1. Per-image signed tickets — chosen

`POST /v1/reels/uploads` creates one pending post plus one pending media row per image. It returns one short-lived ticket per image. The app uploads each image directly, then completes the post once all images match.

Trade-off: more ticket entries and sequential uploads, but retries are image-specific, existing ticket security is reusable, and partial uploads are easy to recover.

### 2. One multipart request for the whole carousel

One ticket authorizes a single multipart request containing up to five images.

Trade-off: fewer round trips, but a failed request is harder to resume and file cleanup is less precise. Rejected because partial-retry behavior matters on mobile networks.

### 3. Cloudinary instead of z.com

Reuse the existing unsigned Cloudinary preset.

Trade-off: simplest client, but the owner explicitly chose z.com. Rejected.

## Data model

Add `app_reel_media`:

- `reel_id CHAR(36)`
- `position TINYINT UNSIGNED` (1–5)
- `image_url VARCHAR(1000) NULL`
- `storage_key VARCHAR(255) NOT NULL`
- `sha256 CHAR(64) NOT NULL`
- `size_bytes INT UNSIGNED NOT NULL`
- `mime_type VARCHAR(50) NOT NULL`
- `width INT UNSIGNED NULL`
- `height INT UNSIGNED NULL`
- `status ENUM('pending','visible','deleted')`
- `created_at`, `updated_at`
- Primary key `(reel_id, position)`, unique `storage_key`.

Keep `app_reels` for caption, owner, post status, timestamps, and counts. `poster_url` stores the first visible image for grids. Legacy video columns remain unused. Feed queries require at least one visible media row, so old video-only rows do not appear.

Storage keys are deterministic: `<reelId>-<position>.<ext>`. Allowed extensions map to `image/jpeg`, `image/png`, and `image/webp`.

## Upload contract

### Init

`POST /v1/reels/uploads` with `Idempotency-Key: <base>-init`:

```json
{
  "caption": "optional, max 300",
  "images": [
    {
      "fileName": "one.jpg",
      "sizeBytes": 123456,
      "mimeType": "image/jpeg",
      "sha256": "64 lowercase hex"
    }
  ]
}
```

Validation: 1–5 images; each 1 byte–10 MB; total ≤50 MB; extension/MIME allowlist; valid SHA-256; fewer than five posts created by the user in the rolling last 24 hours.

Response:

```json
{
  "ok": true,
  "reel": { "id": "uuid", "status": "pending" },
  "uploads": [
    {
      "position": 1,
      "url": "https://ghossthub.com/reels/upload.php",
      "token": "short-lived HS256 ticket",
      "expiresAt": "2026-11-26T12:15:00.000Z",
      "maxBytes": 10485760,
      "sha256": "...",
      "storageKey": "uuid-1.jpg"
    }
  ]
}
```

Ticket claims: `sub`, `reelId`, `position`, `purpose = reel-image-upload`, `sha256`, `sizeBytes`, `mimeType`, `ext`, `jti`, `iat`, `exp`. Tickets last 15 minutes.

### Direct upload

The app sends multipart field `image` to the ticket URL with `Authorization: Bearer <ticket>`.

The host validates ticket, exact size/hash, `finfo` MIME, and magic bytes:

- JPEG: `FF D8 FF`
- PNG: `89 50 4E 47 0D 0A 1A 0A`
- WebP: `RIFF .... WEBP`

It writes the deterministic key with exclusive create. Replaying identical content returns the existing URL; different content returns 409. Response includes `imageUrl`, `sha256`, `sizeBytes`, `width`, and `height`.

### Complete

`POST /v1/reels/{id}/complete` with `Idempotency-Key: <base>-complete`:

```json
{
  "images": [
    {
      "position": 1,
      "imageUrl": "https://ghossthub.com/reels/media/uuid-1.jpg",
      "sha256": "...",
      "sizeBytes": 123456
    }
  ]
}
```

The API verifies ownership, pending state, exact positions/URLs/hashes/sizes, then atomically marks all media and the post visible. `poster_url` becomes position 1. Replaying the same completion succeeds; mismatched data returns 409.

The client derives separate init and completion keys from one random base key. This avoids colliding with the init response in the shared idempotency table.

## Feed and UI

- `Reel` contains ordered `images`; `posterUrl` is the first image.
- Vertical `PageView` remains the post feed.
- Each post contains a horizontal `PageView` carousel and dot indicator.
- No autoplay, mute control, or video player.
- Profile grid uses `posterUrl` with an image placeholder.
- Admin moderation shows image previews and media count.

## Deletion and cleanup

- Owner/admin post deletion removes metadata and asks z.com to delete `<reelId>.mp4` plus `<reelId>-1..5.{jpg,jpeg,png,webp}`.
- Account deletion removes `app_reel_media` rows before `app_reels`, then performs best-effort file deletion after commit.
- The cron expires pending posts after 24 hours, removes their media rows, and deletes partial files.
- Legacy MP4 files remain deletable by the same reel-bound delete ticket.

## Migration and rollout

1. Run `mobile_app_reel_images.sql`.
2. Deploy the main API.
3. Deploy the z.com image uploader with the existing secret/base URL.
4. Publish Firestore rules only if chat rules are not already live.
5. Deploy the admin page and privacy docs.
6. Ship the app.

Rollback: hide the Reels tab or disable Reels config. Do not drop `app_reel_media`, `app_reels`, or z.com media files.

## Acceptance

- One to five images upload in order and display as a carousel.
- Invalid type/size/hash/ticket/position is rejected.
- Partial upload retry succeeds without duplicating the post.
- Old video-only rows are absent from the image feed.
- Likes/comments/follows/reports/moderation/deletion still work.
- Full Flutter/PHP gates and release build pass.
