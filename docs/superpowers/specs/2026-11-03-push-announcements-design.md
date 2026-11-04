# Push notifications + in-app announcements — design

## Intent

Users get a system notification even with the app closed and even if killed:
when a new product is listed, when an out-of-stock product is restocked, and
when the owner posts a manual announcement. Manual announcements must also
show as a banner inside the app.

## Goals

- Automatic push on `products_create` (new active product) and on restock.
- Manual announcement composed inside the app's admin screen (`is_admin`).
- Manual announcement appears as an in-app banner on the home shell until the
  user dismisses it.
- Push failures never break the admin action that triggered them.

## Non-goals

- Per-user targeting, read receipts, notification history screen.
- Re-prompting, quiet hours, notification categories beyond OneSignal defaults.
- iOS (project is Android-only).
- Deleting a OneSignal subscription on account deletion: we never send the
  user's account id to OneSignal, so no account data lives there to delete.
  The device stays subscribed to broadcast announcements. Non-issue because
  announcements carry no PII and are the same for every device.

## Anti-goals

- A token table we have to keep clean. No `app_push_tokens`.
- Any notification that reveals a key, an email, or a coin balance.
- A client-side send path. Only the API talks to OneSignal.

## Constraints

- Android push while the app is closed needs a push service. OneSignal's
  Android SDK still requires Firebase/FCM credentials: `google-services.json`
  in the app + the FCM service-account JSON uploaded to the OneSignal
  dashboard. This is a manual step for the owner, not code.
- The app has no Firebase plugin today (`android/app/build.gradle.kts` has no
  `google-services` plugin, no `google-services.json`).
- The API is plain PHP 8 on Hostinger; secrets live in `api/config.php` with
  `getenv()` overrides, blank means "feature off" (same pattern as Cloudinary).
- The app's HTTP layer is `lib/api/` + `Backend` in
  `lib/services/worker_backend.dart`; screens never call Dio directly.
- The `direct` flavor has `applicationIdSuffix = ".direct"`, so it installs as
  `com.astrixtech.ghosst.direct`. The Google Services Gradle plugin fails the
  build for a variant with no matching `client` in `google-services.json`, so
  **both** package names must be registered as Firebase Android apps (owner,
  one-time console step) and the merged `google-services.json` drops into
  `android/app/`.

## Approaches

**A. FCM directly** — `firebase_messaging`, token table, PHP HTTP v1 sender
(service-account JWT + token cache). Most control, most code: ~300 lines plus
token lifecycle and account-deletion cleanup.

**B. OneSignal + admin compose (chosen)** — `onesignal_flutter` initialises
with the app id; broadcast to all subscribed devices. No token table, no
external ids: OneSignal already holds the subscriptions. PHP only needs one
`push_send()` helper (REST API, cURL, 5 s timeout, errors logged not thrown).
Trade-off: a third-party account and the FCM credentials anyway; but ~60 lines
of PHP and nothing to clean up per user.

Rejected: OneSignal dashboard-only manual sending (owner wanted it in the admin
screen), and polling (cannot notify a killed app).

## How it works

### App

- `onesignal_flutter` dependency. `lib/services/push.dart` holds the OneSignal
  app id (`--dart-define=ONESIGNAL_APP_ID` override, default filled after the
  dashboard app is created) and `Push.init()` / `Push.requestPermission()`.
- `main.dart`: `Push.init()` once at startup (fire-and-forget, never blocks
  launch), `Push.requestPermission()` after a session exists — Android 13+
  runtime prompt, and the launch gates must not be bypassed by a dialog.
- Nothing else. If the SDK fails to initialise, the app works as today.

### API

- New table `app_announcements`: `id` (uuid PK), `title` varchar(120),
  `body` text, `active` tinyint(1) default 1, `expires_at` datetime,
  `created_at` datetime. `GET /v1/announcements` returns the newest row where
  `active = 1 AND (expires_at IS NULL OR expires_at > UTC_TIMESTAMP())`.
  Manual announcements get `expires_at = now + 7 days`; auto product/restock
  pushes are not stored as announcements at all (they are notifications only).
  DDL: `CREATE TABLE IF NOT EXISTS` in a new
  `C:\laragon\www\database\app_announcements.sql` (the existing dump has no
  `app_*` tables), run once on Hostinger and pasted into SETUP.md.
- `api/lib/push.php`: `push_send(string $title, string $body, string $url)`.
  Reads `ONESIGNAL_APP_ID` / `ONESIGNAL_REST_KEY` from `api/config.php`; blank
  key = no-op returning false. Guard against accidental broadcasts from a dev
  box: the call is skipped unless `HTTP_HOST` is `ghossthub.com` (or the
  `GHOSST_PUSH_HOST` env override), and the skip is logged. All subscribed
  devices are targeted (no `include_subscriptions`). Deep link left empty (the
  app has no router). Catches everything, `error_log('push failed: ...')`,
  returns bool.
- `api/routes/announcements.php`
  - `POST /v1/admin/announcements` (admin): validates title/body, inserts the
    row, calls `push_send()` after the insert, returns `{announcement, pushed}`.
  - `GET /v1/announcements` (auth required): newest unexpired, active row,
    `{announcement: {id, title, body, createdAt} | null}`.
- `api/routes/products.php` `products_create`: after the insert and only when
  the new product is active, `push_send('Bagong product', $name, '')`.
- `api/routes/keys.php` `keys_add`: count available keys for the product **and
  duration** before the insert; when that pool was 0 and `$added > 0`, push
  `'Bagong stock: <product> — <duration>'`. Restocking an already-stocked pool
  stays silent, so a bulk paste cannot spam: only the first batch after a
  sell-out notifies. Products without durations behave as one pool (`duration`
  empty).

### In-app banner

- `Backend.announcement()` → `GET /v1/announcements`; `Backend.sendAnnouncement
  (title, body)` → admin POST. Both live in `worker_backend.dart` /
  `api_backend.dart` like every other call.
- `HomeShell` (`lib/main.dart`) fetches the announcement with `_refresh()` and
  renders a dismissible strip above the page content: accent border, bold
  title, body, close `IconButton`. Failure = no banner, never an error toast.
- Dismissed id persisted in `lib/services/announcement_store.dart`
  (`flutter_secure_storage`, already a dependency) so a review-once banner does
  not return on every launch. Show only when `storedID != announcement.id`.
- Admin screen: one `GlowCard` at the top — title field, body field, Send button
  disabled while sending, success/error reuses the existing `message` strip.

## My calls

- Broadcast to all devices, no per-user segment: kills the token table and the
  account-deletion edge case.
- Restock push per duration pool, 0 → >0, with the duration in the title.
- Announcements expire 7 days after posting; `active` stays for takedown.
- `GET /v1/announcements` requires auth: the banner only shows inside
  `HomeShell`, which is post-login.
- Push never fails the request; `pushed` in the admin response is informational.
- Title length 120, body required, trimmed; blank key or non-prod host means the
  feature is silently off.
- `docs/index.html` (Play-linked privacy policy) gains one paragraph: the app
  uses Firebase Cloud Messaging through OneSignal for device notifications, and
  no account data is shared with it. The Play Data Safety form is the owner's
  to update; this is noted in the handover, not blockable from code.

## Left to the builder

- Exact OneSignal dashboard steps and the wording of the setup note for the
  owner (app id, FCM service-account JSON, confirming an installed device shows
  under Subscriptions).
- Whether the banner sits above or below the coin header — pick whichever
  costs the smaller diff in `HomeShell`.
- Exact PHP placement of the pre-insert stock count (one query, same route).

## Verification

- `flutter analyze`, `flutter test`.
- New widget test: banner renders for a new announcement id and disappears
  after dismiss; no banner when the returned id equals the stored one.
- PHP: no test harness in the project; verify by calling the two endpoints
  against the local `php -S` server with a seeded admin token, and check the
  OneSignal dashboard "Sent" log plus a real device with the app killed.
- Order of manual checks: one push received while the app is closed, one
  product-create push, one restock push after a pool sells out, one silent add
  on a stocked pool, and one announcement past `expires_at` no longer showing.
  Run them on a `play` build and a `direct` build (both packages registered in
  Firebase, otherwise `flutter build apk --flavor direct` fails loudly).
