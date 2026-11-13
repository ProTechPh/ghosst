# SETUP — Ghosst (Flutter + PHP/MySQL API + AdMob SSV)

The app has **one backend**: a plain PHP 8 API on Hostinger at
`https://ghossthub.com/api/v1`, talking to MySQL. It is the same REST contract
the Cloudflare Worker used to serve, so the Flutter code did not change — only
`ApiConfig.baseUrl`. There is no Appwrite, no Firebase, no Cloudflare.

| Piece | Where |
|---|---|
| Live API | `https://ghossthub.com/api/v1` |
| API source | `C:\laragon\www\api\` — deployed to `public_html/api/` (not in this repo) |
| Database | MySQL `khctcfuv_ghosst` on Hostinger — accounts sa `users`, ang app data sa `app_*` |
| Schema + data | `ghosst-web/database/` (dump + `app_announcements.sql`), `api/migrate_app_users.php` |
| Flutter client | `lib/api/` (Dio) + `lib/services/worker_backend.dart` |
| Images | Cloudinary (unsigned upload preset `ghosst`) |

`api/README.md` is the API's own doc (deploy, rollback, unported features);
this file is the app-side setup.

## 1. Data model (MySQL)

Ang accounts ay nasa website table na `users` — iisa na ang account ng app at ng
site (parehong email/password, parehong `id`). Ang `users` ay may dagdag na
column para sa app: `coins`, `display_name`, `is_admin`, `is_moderator`,
`chat_muted`, `muted_until`, `deleted_at`, `announcements_seen_at`,
`chat_seen_at_ms`. Ang `balance` ay pera ng site; ang `coins` ay app rewards —
huwag paghalo.

Ang natitirang `app_*` tables ay nasa tabi ng 36 site tables at `users.id` (int)
ang `user_id` nila: `app_sessions` (refresh tokens, SHA-256 lang ang nakatago),
`app_products`, `app_product_images`, `app_product_durations`,
`app_product_files` (MediaFire link ng apk/file products), `app_keys`
(`UNIQUE(product_id, key_value)`), `app_claims` (`ux_app_claims_owned` makes
app/file products single-purchase), `app_ad_rewards` (SSV dedupe, PK = AdMob
`transaction_id`), `app_idempotency` (`idem_key`, PK `(user_id, idem_key)`),
`app_announcements` (manual banner/push text, 7-day `expires_at`).

Bagong DB: i-apply ang `database/mobile_app_schema.sql` tapos
`app_announcements.sql`. Lumang DB na may `app_users` (walang downtime sa app):

1. I-upload lang ang `api/migrate_app_users.php`, tapos
   `php api/migrate_app_users.php --apply` (schema + data, buhay pa ang
   lumang `app_users`).
2. I-upload ang buong bagong `api/` (`T_USERS = 'users'`).
3. `php api/migrate_app_users.php --apply --retire-app-users` (huling coins sync
   + rename ng `app_users`).

Kumuha muna ng dump bago ang unang `--apply` — hindi na maibabalik ang
UUID → int. Ang lumang `app_users` ay nire-rename (hindi DROP) para may
rollback copy, at ang mga na-overwrite na site password ay nasa
`users_password_backup`.

Kung phpMyAdmin lang ang gamit: `database/mobile_app_schema.sql`,
`mobile_app_data.sql` (one-shot D1 copy — re-running duplicates rows) at
`app_announcements.sql`. Run `app_announcements.sql` **before** uploading
`api/`: an app that calls `GET /v1/announcements` against a missing table logs a
500 on every launch.

## 2. Admin

There is no team/console UI. An account becomes admin with one statement:

```sql
UPDATE users SET is_admin = 1 WHERE email = 'you@example.com';
```

Sign out and back in afterwards — the app caches `isAdmin` for the session.
The **Admin** tab appears for admins only (`users.role` is the site's own admin
flag; hindi ito ginagamit ng app).

Coins are server-side only. To hand yourself some for testing:

```sql
UPDATE users SET coins = 100 WHERE email = 'you@example.com';
```

## 2b. Google sign-in (app + web)

Ang bagong account sa app ay gawa ng **Google**; ang email+password ay
sign-in lang para sa lumang accounts (walang reset sa app). Parehong `users`
row ang hinahanap ng app at web sa email, kaya isa lang ang account.

1. Google Cloud Console → project `578056640322` (ang may web client ng
   ghossthub.com) → **APIs & Services → Credentials → Create credentials →
   OAuth client ID → Android**. Dalawa, parehong release SHA-1
   (`6B:69:BA:D0:66:86:46:36:EA:20:C7:44:03:DF:EF:D9:C4:6C:75:C5`):
   - package `com.astrixtech.ghosst` (play flavor)
   - package `com.astrixtech.ghosst.direct` (direct APK)

   Kung mag-sesideload ka ng debug build, idagdag din ang debug SHA-1
   (`cd android; ./gradlew signingReport`).
2. Walang kailangang baguhin sa `google-services.json` — ang Web client ID sa
   `lib/services/google_auth.dart` (`googleServerClientId`) ang
   `serverClientId`, at iyon din ang `GOOGLE_CLIENT_ID` sa `api/config.php`.
   Kapag pinalitan, dapat pareho ang dalawa.
3. Test: Sign out sa app → **Continue with Google** → dapat pumasok sa Home
   gamit ang email ng Google account. Ang bagong account ay may random
   password (hindi alam ng user); ang lumang account ay hindi ginalaw ang
   password, kaya gumagana pa rin ang email sign-in.

Symptom → sanhi:

| Symptom | Sanhi |
|---|---|
| `Google sign-in is not available right now` | Kulang ang Android OAuth client para sa package + SHA-1 (release vs debug), o walang Google Play services |
| `ApiException: Google sign-in failed` | `aud` ng ID token ay hindi tugma sa `GOOGLE_CLIENT_ID` (magkaibang project ang web client ng app at ng API) |
| Pumasok pero bagong account na 0 coins | Ibang email ang Google account kaysa sa app account — gamitin ang email sign-in |

## 3. AdMob

Every unit ID lives in `lib/services/ad_service.dart` (`class AdUnits`).

| Format | Purpose | Where it shows |
|---|---|---|
| Rewarded | coins (SSV) | Earn tab — "Watch ad & earn coins" |
| Rewarded interstitial | coins (SSV) | Earn tab — "Instant ad & earn coins" |
| Interstitial | revenue only | every other tab switch, ≥45 s cooldown |
| Banner | revenue only | strip under the app bar (never against the nav) |
| Native (medium) | revenue only | "Sponsored" card at the end of the Store |

App ID (already in the manifest): `ca-app-pub-7791552060229072~1855578469`.

1. **Rewarded units** (both): Ad unit → **Edit** → **Server-side
   verification** → set the bare URL
   `https://ghossthub.com/api/v1/ads/ssv` → **Verify URL** → **Save**.
   Tick **Apply to all networks in Mediation groups** before saving: without
   it a Unity-filled rewarded view never calls the SSV URL, so the user
   watches the ad and is never paid.
   Reward amount = coins per ad (currently `10`); it comes back as
   `reward_amount` in the signed callback. `/v1/ads/status` must expose the
   same number as `coins_per_reward` — the Earn screen advertises that value.
2. **Coins never arrive?** The API logs every rejection to PHP's error log
   (`SSV blocked: <reason>`). On Hostinger that is
   `public_html/logs/` / `error_log` in the File Manager. No log line at all
   ⇒ the callback URL is wrong in AdMob. A logged signature error ⇒ the
   verifier keys could not be fetched, not your URL.
3. **Unity Ads mediation fallback:** AdMob → Mediation → a rewarded group
   targeting both rewarded units, then Unity Ads as an ad source. Merely
   shipping `gma_mediation_unity` does not enable Unity inventory; startup
   logs must show `Unity Ads Adapter: ready`.
4. **`app-ads.txt`:** `https://ghossthub.com/app-ads.txt` must serve the
   publisher line for the website on the Play listing. Missing it lets other
   domains resell your inventory and can cost you demand.
5. **Ad-blocker gate:** `lib/services/adblock_detector.dart` probes AdMob
   hosts with `$API_BASE_URL/products` as the control. 2 of 3 ad hosts
   blocked while the control answers = gate (`lib/screens/adblock_screen.dart`,
   third gate in `main.dart`, re-checked on resume). Fails open when offline or
   inconclusive; Private DNS is shown as context, never a standalone trigger.
6. **Coin-farm guards** (`api/lib/rewards.php`, enforced in `routes/ads.php`
   after the signature check, before the credit):
   - `ad_unit` must sit under our publisher id `ca-app-pub-7791552060229072/`.
     A callback signed for anyone else's ad unit is their ad, not ours.
   - 50 paid rewards per account per rolling 24 h, minimum 15 s apart. The
     30 s cooldown in the app is client-side and dies with an APK patch.
   - One reward per `transaction_id`; callbacks without one are keyed by their
     signed payload hash, so a replay cannot create a second credit.
   - A single reward is capped at 1000 coins, so a wrong AdMob reward setting
     cannot mint a balance.
   - Pacing is keyed on `sha256(lower(email))`, so deleting and re-registering
     the same address does not reset the daily cap.
   - 60 rewards per install per window, keyed on the hashed install id the app
     sends as SSV `custom_data` (`lib/services/install_id.dart`). Rejections log
     `SSV blocked: device_cap`. The column is created lazily on the first
     callback; `database/mobile_app_ad_device.sql` adds it plus the index.
   Each rejection writes `SSV blocked: <reason>` — check the error log before
   assuming the callback URL is wrong.

## 4. Run & test

```powershell
flutter pub get
flutter analyze                 # the only lint gate
flutter test                    # no network needed
flutter run --flavor play
# sideload-only feature set:
flutter run --flavor direct
# QA ads:
flutter run --release --flavor play --dart-define=USE_TEST_ADS=true
# live units on your own device: register it as a test device first, or your
# own taps count as invalid traffic.
flutter run --release --flavor play --dart-define=TEST_DEVICE_IDS=ABC123DEF456
flutter build appbundle --release --flavor play --dart-define=USE_TEST_ADS=false
flutter build apk --release --flavor direct
```

The API base URL defaults to production; point it at a local server with
`--dart-define=API_BASE_URL=http://127.0.0.1:8099/v1` after starting
`php -S 127.0.0.1:8099 -t C:\laragon\www\api C:\laragon\www\api\index.php`.

1. Sign up → **Admin** appears for an admin account.
2. Admin: **New product** → name, cost, image (Cloudinary picker or URL) →
   **Add product**. Key products: paste keys, one per line → **Add keys**.
   APK/File products: paste a MediaFire page or direct URL.
3. Earn: **Watch ad & earn coins** → the app polls your balance until the SSV
   callback lands (usually seconds, up to a minute; coins still arrive after
   the timeout message).
4. Store → **Claim** → key shown + copied → **Purchases**.

### 4.1 MediaFire notes

- Upload the file to MediaFire yourself (web or app), copy the share link,
  paste it in the Admin product form. The app resolves page links → direct
  link at download time (no JS needed).
- Page links are safer to store than `downloadNN.mediafire.com` direct links —
  the latter rotate and expire.
- No MediaFire account is needed to *download*; hosting needs an uploader.
  Free accounts are capped at ~50 GB/day of direct downloads.

## 5. Release checklist

- [ ] Real AdMob app ID in the manifest and real unit IDs for all five formats
      in `AdUnits`, and SSV enabled on **both rewarded units** pointing at
      `https://ghossthub.com/api/v1/ads/ssv`, with **Apply to all networks in
      Mediation groups** ticked (otherwise Unity fills pay nothing).
- [ ] `https://ghossthub.com/app-ads.txt` serves the publisher line.
- [ ] Reward pacing is not email-only: add per-IP and per-device caps and make
      Play Integrity blocking for SSV credits. Registering a new address must
      not reset the budget — coins convert to sellable keys, so a farmer is
      your suspension risk, not the SDK's.
- [ ] `api/` uploaded to `public_html/api/` and the SQL files applied to the
      production DB — including `database/mobile_app_ad_device.sql` (the
      column self-creates on first use; the file adds the index).
- [ ] `JWT_SECRET` in `api/config.php` changed from the placeholder.
- [ ] `CLOUDINARY_API_SECRET` set, so deleting a product also deletes its
      images.
- [ ] Push notifications: `NOVU_API_URL` / `NOVU_API_KEY` set in
      `api/config.php` on the host (blank = push silently off), and
      `android/app/google-services.json` present with **both** packages
      (`com.astrixtech.ghosst`, `com.astrixtech.ghosst.direct`). See §8.
- [ ] Each published APK/file product has a working MediaFire link.
- [ ] Play upload uses the `N` from CI: every push to `main` auto-bumps
      `version: x.y.z+N` in `pubspec.yaml` and publishes `vX.Y.Z+N`. Bump
      `x.y.z` by hand only when the feature version changes.
- [ ] Use the right GitHub Release asset: `live-ads.aab` for production Play,
      `closed-beta-test-ads.aab` for closed testing, `release-live-ads.apk` /
      `release-test-ads.apk` for sideload QA. Never promote a `test-ads` bundle
      to Production. QA builds carry a `versionCode` 500 higher than the live
      one, and CI refuses to publish if an AAB is missing its expected ad unit.
- [ ] Upload `mapping.txt` from the run's **Actions artifact** (never the
      release page — it is private on purpose) to Play (App bundle explorer →
      version code → Upload deobfuscation file). R8 is on for release builds.

## 6. Troubleshooting

| Symptom | Likely cause |
|---|---|
| Every request `500 internal` | DB unreachable or a table/column missing — check `api/config.php` credentials, then the error log |
| Coins never arrive after a real ad | No `SSV blocked` and no credit line in the error log ⇒ callback URL wrong in AdMob |
| `401` right after opening the app | Refresh token expired/revoked — sign in again |
| Admin tab missing | `users.is_admin = 0` for that account, or the app still holds the cached session (sign out/in) |
| Store shows no products | Create one in Admin, `active = 1` |
| Buy app → `Download not configured` | No `app_product_files` row for that product — re-save the link in the Admin edit dialog |
| Download stuck / `Could not resolve` | MediaFire link invalid or page changed — paste a fresh share link |
| APK won't install | `REQUEST_INSTALL_PACKAGES` missing from the manifest (play flavor) or "install unknown apps" disabled for Ghosst |
| Release: `Missing classes detected while running R8` | Copy the `-dontwarn` lines from `build/app/outputs/mapping/<variant>/missing_rules.txt` into `android/app/proguard-rules.pro` |
| Release: `Gradle build daemon disappeared` | `org.gradle.jvmargs` too big for the machine — 4G works on 12 GB Windows and 7 GB CI runners |
| No notification arrives | `google-services.json` missing or its package name does not match the installed flavor; Firebase service-account JSON not in Novu → Integrations → FCM; `ghosst-broadcast` not published; subscriber missing from topic `ghosst` (check Novu → Subscribers); `NOVU_API_KEY` blank or a dev host (skipped on purpose) |

## 7. Trust boundaries

- Coins move **only** in the API: acquired via a signed AdMob SSV callback
  (ECDSA P-256 over the raw query string, verified with `openssl_verify`
  against Google's published keys), spent inside a MySQL transaction that
  locks the user row (`SELECT coins ... FOR UPDATE`) before touching a key.
- Keys stay server-side: only `GET /v1/claims` (owner-scoped) returns the key
  text. Download links are different — the claim response and `downloads/:id`
  hand the buyer the `downloadUrl` itself, and MediaFire keeps a copied link
  valid, so deleting a claim does not revoke it. That is why APK/file products
  are single-purchase.
- Untrusted input is validated at the edge: JWT signature, 1 MB body cap,
  server-side validation of every field the Admin form sends.
- A modded client can only send requests faster; idempotency + the locked
  transaction make that useless.

## 8. Push notifications (Novu self-hosted + FCM)

The API broadcasts through the Novu instance at `novu.astrixstudio.tech`; the
app only reports its FCM token, keyed by the anonymous install id. Everything
here is optional: with a blank API key, or on any host other than
`ghossthub.com`, `push_send()` logs `push skipped` and the feature is off.

**One-time setup (owner):**

1. Firebase project `ghosst-6f23e` → Project settings → Service accounts →
   Generate new private key. Upload **that** JSON (not `google-services.json`,
   which is rejected — wrong file) to Novu → Integrations → **FCM (Android)**.
2. Firebase: one project holds **both** Android apps,
   `com.astrixtech.ghosst` and `com.astrixtech.ghosst.direct` (the `direct`
   flavor has `applicationIdSuffix = .direct`). Their merged config is checked
   in at `android/app/google-services.json`; the Google Services plugin is in
   `android/settings.gradle.kts` + `android/app/build.gradle.kts`. Both apps
   must stay registered or the build fails for that flavor.
3. Novu → Workflows → new workflow `ghosst-broadcast` with one **Push** step:
   subject `{{payload.title}}`, body `{{payload.body}}`. Publish it in the
   environment the API key belongs to.
4. Topic `ghosst` is created by the first device registration; no manual step.
5. In `api/config.php` on Hostinger set `NOVU_API_URL` (the Novu API root),
   `NOVU_API_KEY` (Novu → API keys, never committed), `NOVU_WORKFLOW_ID` and
   `NOVU_TOPIC_KEY`; optional `NOVU_FCM_INTEGRATION` when more than one FCM
   integration exists. Env overrides are `GHOSST_NOVU_*`.

The app registers its token at `POST /v1/push/register` on every launch and on
every rotation; the endpoint is public so signed-out devices still get
broadcasts, exactly like the old OneSignal device subscription. It always
answers `{ok:true}` and logs `push register skipped` / `novu failed` instead of
failing the request.

**What sends a notification:** a new product (`products_create`), a sold-out
duration pool getting keys again (`keys_add`, silent on top-ups), and the
Admin tab's announcement card (saved in `app_announcements`, shown as a
dismissible banner for 7 days). Pushes are fire-and-forget: a failed send is
logged (`novu failed: ...` / `push skipped: host/key`) and never fails the
admin request.

With the app in the foreground Android shows no tray notification; the shell
reloads on the message instead, so the announcement appears as the banner.

Before the first broadcast, confirm `NOVU_API_URL` is the API and not the
dashboard: `<NOVU_API_URL>/v1/subscribers` with the `ApiKey` header must answer
JSON (401 without the header is fine), not an HTML page.
