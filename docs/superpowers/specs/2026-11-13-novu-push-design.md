# Novu push migration (OneSignal → self-hosted Novu) — design

## Intent

Deliver the same three broadcast notifications (new product, sold-out pool
restocked, admin announcement) through the self-hosted Novu at
`novu.astrixstudio.tech`, so every AstrixTech app shares one notification stack.
Big-bang cutover: OneSignal is removed in the same release. Owner picked this
over a dual-send transition (B), accepting that already-installed APKs go silent
until they update.

## Goals

- One title/body push per event, to every device. App in background/killed: the
  Android tray shows it. App in front: FCM does not display notifications there,
  so the shell reloads and the announcement appears as the in-app banner — same
  end result, no duplicate tray entry. `pushed` in the admin response keeps
  meaning "handed to the sender".
- No account data to Novu. Subscriber id = the existing anonymous `InstallId`
  (32 hex, per install), same stance as today's anonymous OneSignal device.
- Fail-open: Novu being down/slow never fails the admin action that fired it.
- One dashboard for all AstrixTech apps.

## Non-goals

- Novu Inbox / notification centre, per-user preferences, email/SMS/chat steps.
- Deleting the Novu subscriber on account deletion: the install id is a device
  pseudonym, not account data, and carries no PII.
- Migrating OneSignal history or subscriptions.

## Current state

- `lib/services/push.dart`: OneSignal SDK init + permission ask, gated so the
  dialog never covers the splash/gates (`splashDone`, `canAsk`).
- `ghosst-web/api/lib/push.php`: `push_send()` → OneSignal REST, segment
  `Total Subscriptions`; 3 s connect / 5 s total; errors logged, never thrown.
- Callers: `routes/products.php` (new active product), `routes/keys.php` (only
  when a pool goes 0 → >0), `routes/announcements.php` (after the row is saved).
- `PUSH_HOST` guard: only `ghossthub.com` broadcasts; every other host logs
  `push skipped`.
- `install_id.dart` already produces a stable 32-hex id in secure storage
  (used as AdMob SSV `custom_data`).
- Firebase is already initialised by `ChatService.init()`; `google-services.json`
  and the google-services Gradle plugin are in place; no `firebase_messaging`.

## Registration (new)

- App, every launch after Firebase is up: `FirebaseMessaging.instance.getToken()`
  → `POST /v1/push/register {installId, token}`; `onTokenRefresh` re-posts.
- Route: `['POST', '#^/v1/push/register$#', 'push_register', 'none']`. No auth:
  push must also reach the signed-out landing page, exactly like OneSignal did.
- Handler (`routes/push.php`) validates `installId ^[0-9a-f]{32}$` and a token of
  100–4096 chars, then makes three Novu calls, each with 3 s/5 s timeouts:
  1. `POST /v1/subscribers` `{subscriberId: installId}` — 409 = exists, fine.
  2. `PUT /v1/subscribers/{installId}/credentials`
     `{providerId: "fcm", credentials: {deviceTokens: [token]}}`
     (+ `integrationIdentifier` only when `NOVU_FCM_INTEGRATION` is set).
  3. `POST /v2/topics/{topic}/subscriptions`
     `{subscriptions: [{identifier: installId, subscriberId: installId}]}`.
- Always answers `{ok: true}`; failures are only logged. The app re-registers on
  the next launch, so there is no retry machinery.

## Send

- `push_send($title, $body)` → `POST /v1/events/trigger`
  `{name: NOVU_WORKFLOW_ID, to: {type: "Topic", topicKey: NOVU_TOPIC_KEY},
  payload: {title, body}}`.
- Novu workflow (dashboard, once): Push step, subject `{{payload.title}}`,
  body `{{payload.body}}`. Novu sends an FCM `notification` message, so Android
  displays it with the app killed — no background handler needed.
- Timeouts, logging and the boolean return stay exactly as today, so the three
  callers need no change.
- Topic, not Novu Broadcast: the environment may be shared with other AstrixTech
  apps, and broadcast would hit every subscriber in it.

## Config (`ghosst-web/api/config.php`)

| define | env override | value |
| --- | --- | --- |
| `NOVU_API_URL` | `GHOSST_NOVU_API_URL` | API root, e.g. `https://novu.astrixstudio.tech` |
| `NOVU_API_KEY` | `GHOSST_NOVU_API_KEY` | dashboard → API keys, never committed |
| `NOVU_WORKFLOW_ID` | `GHOSST_NOVU_WORKFLOW_ID` | workflow trigger id, e.g. `ghosst-broadcast` |
| `NOVU_TOPIC_KEY` | `GHOSST_NOVU_TOPIC_KEY` | `ghosst` |
| `NOVU_FCM_INTEGRATION` | `GHOSST_NOVU_FCM_INTEGRATION` | optional identifier |

`ONESIGNAL_APP_ID` / `ONESIGNAL_REST_KEY` are deleted (the REST key is currently
committed — removing it is a side win). `PUSH_HOST` stays.

## App changes

- `pubspec.yaml`: drop `onesignal_flutter`, add `firebase_messaging`.
- `lib/services/push.dart`: rewritten without an app id. `init()` = Firebase up →
  `getToken()` → `Backend.registerPush(installId, token)` → `onTokenRefresh`
  listener; `requestPermission()` → `FirebaseMessaging.instance.requestPermission()`
  (Android 13+ `POST_NOTIFICATIONS`). `splashDone`/`canAsk` gating unchanged.
- `main.dart`: `Push.init()` now runs after `ChatService.init()` (chained in the
  existing `unawaited(...)`). `Firebase.initializeApp()` throws duplicate-app if
  called twice, and `ChatService` would then set `_ready = false` — chat breaks.
- `Backend.registerPush(...)` + `ApiBackend.registerPush(...)` via `ApiClient`.
- `AndroidManifest.xml`: add `android.permission.POST_NOTIFICATIONS` (OneSignal's
  AAR declared it; Firebase Messaging does not).

## Docs

- `docs/index.html`: replace the OneSignal paragraph with Novu (self-hosted by
  AstrixTech) + Firebase Cloud Messaging (Google) — still an anonymous push
  identifier, no email/coins/purchase data.
- `SETUP.md` §8: Firebase **service-account JSON** (not `google-services.json`)
  → Novu → Integrations → FCM; create the workflow + topic; the config table
  above; troubleshooting row (no notification → subscriber missing from the
  topic / service account wrong / `PUSH_HOST`).

## Tests

- `ghosst-web/api/tests/push_test.php` (same style as `rewards_test.php`):
  install-id and token validation, trigger payload shape, disabled-when-blank
  config. No network.
- Flutter: `main()` is not run by widget tests, so nothing new to mock;
  gate is `flutter analyze` + `flutter test`.

## Risks the owner must know

- Installed APKs stop getting push at deploy time until they update (chosen).
- Novu's uptime is now push uptime; failures are visible only in the PHP log,
  same as today's OneSignal failures.
- Fan-out: one workflow event per subscriber per broadcast; a slow self-hosted
  instance lags behind OneSignal's managed edge.
- The register endpoint is public and unthrottled: every call with a valid-looking
  pair creates a Novu subscriber plus a topic membership. Fake or abandoned
  installs inflate the topic, and a topic trigger fans out one job and one FCM
  send **per subscriber**, so the blast radius is delivery cost and latency, not
  just log noise. Same exposure class as the already-public `POST /v1/auth/register`;
  rate-limit `/v1/push/register` at the edge if it is ever abused, and prune
  subscribers idle for ~90 days.
- Endpoint paths (`/v1/subscribers`, `/v1/events/trigger`, `/v2/topics/...`)
  will be confirmed against the instance version during implementation; Novu
  has v1 and v2 surfaces side by side.

## Needed from the owner (dashboard, not code)

1. Firebase service-account JSON into Novu → Integrations → FCM Android.
2. One workflow `ghosst-broadcast` with a Push step (`{{payload.title}}` /
   `{{payload.body}}`).
3. Topic key `ghosst` (auto-created by the first subscription).
4. `NOVU_API_URL`, API key, workflow id, topic key for `api/config.php`.
