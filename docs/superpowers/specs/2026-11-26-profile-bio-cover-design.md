# Profile Bio & Cover Photo — Design

**Date:** 2026-11-26

## Intent

The user wants their own profile to support editing a bio and uploading a cover
photo, TikTok-style. Today the profile shows a static tagline and a solid black
header band; there is no storage or API for either field.

## Goals

- Bio (up to 300 chars, plain text) is editable and shown on own and public
  profiles.
- Cover photo is picked from the gallery, uploaded to the site's FTP host, and
  shown as the profile header band.
- Existing profile behavior (stats, reels, overflow menu) stays intact.

## Non-goals

- No display-name, username, or avatar editing in this change.
- No cover cropping UI, no multiple covers, no reels changes.
- No new storage host — cover images go to the same FTP host as product images.

## Constraints

- `users` table gets `bio VARCHAR(300) NOT NULL DEFAULT ''` and
  `cover_url VARCHAR(1000) NULL`. Migration is a one-shot SQL file; the user
  runs it on Hostinger (this repo cannot apply it).
- API must tolerate the columns being absent before migration: use the existing
  `social_column_exists()` pattern so public reads fail open.
- Cover upload: JPG/PNG/WebP, max 5MB, stored under `uploads/covers/`, returned
  as a relative path plus an absolute URL via `PUBLIC_CDN`.
- Bio is plain text: reject HTML tags, cap length.
- `flutter run` is never used for verification; use `flutter analyze` and
  `flutter test`.

## Approaches

- **A (picked):** add two columns to the shared `users` row and two small API
  endpoints, mirroring the existing `avatar_url` pattern. Fewest new tables and
  joins.
- **B (rejected):** a separate `app_profiles` table keyed by user id. Cleaner
  isolation but a new table, joins in every profile read, and a bigger deploy.

## Decided how

1. **Migration:** `ghosst-web/database/mobile_app_profile_fields.sql` adds the
   two columns with an `information_schema` guard so re-running is harmless.
2. **API:**
   - `POST /v1/me/profile` with `{bio}` → `{ok, bio}`; validates plain text,
     1..300 chars (empty clears it).
   - `POST /v1/uploads/cover` multipart `image` → `{ok, path, url}`; reuses the
     website upload validator's rules but writes to `uploads/covers/`.
   - `social_public_user()` adds `bio` and `coverUrl` from the row (guarded by
     `social_column_exists()`), so both own and public profiles receive them.
3. **Flutter:**
   - `PublicUser` gains `bio`/`coverUrl` optional fields, parsed defensively.
   - `ProfileHubScreen` renders `coverUrl` as the header band (black fallback),
     shows the user's bio (static tagline fallback), and adds an **Edit profile**
     action in the app bar.
   - Edit sheet: bio `TextField` (max 300), **Change cover** picker, **Save**
     button; calls `Backend.updateBio()` and, when a file was picked,
     `Backend.uploadCover()` then saves.
4. **Tests:** injected loaders/save callbacks; cover/bio display, empty fallbacks,
   save dispatch, and 320px layout.
5. **Docs:** AGENTS.md, SETUP.md describe the migration step and new endpoints.

## Left to builder

- Decide the exact toolbar placement of the Edit action relative to Share and
  the overflow menu (keep all three reachable).
- Verify with `flutter analyze` and `flutter test`; PHP `php -l` on changed files.
