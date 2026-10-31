# SETUP — Ghosst (Flutter + PHP/MySQL API + AdMob SSV)

The app has **one backend**: a plain PHP 8 API on Hostinger at
`https://ghossthub.com/api/v1`, talking to MySQL. It is the same REST contract
the Cloudflare Worker used to serve, so the Flutter code did not change — only
`ApiConfig.baseUrl`. There is no Appwrite, no Firebase, no Cloudflare.

| Piece | Where |
|---|---|
| Live API | `https://ghossthub.com/api/v1` |
| API source | `C:\laragon\www\api\` — deployed to `public_html/api/` (not in this repo) |
| Database | MySQL `khctcfuv_ghosst` on Hostinger, tables `app_*` |
| Schema + data | `C:\laragon\www\database\mobile_app_schema.sql`, `mobile_app_data.sql` |
| Flutter client | `lib/api/` (Dio) + `lib/services/worker_backend.dart` |
| Images | Cloudinary (unsigned upload preset `ghosst`) |

`api/README.md` is the API's own doc (deploy, rollback, unported features);
this file is the app-side setup.

## 1. Data model (MySQL)

Ten `app_*` tables live beside the website's own 36 tables and never touch them:
`app_users` (email, password hash, coins, is_admin, `web_user_id` → website
`users.id`), `app_sessions` (refresh tokens, only the SHA-256 is stored),
`app_products`, `app_product_images`, `app_product_durations`,
`app_product_files` (the MediaFire link for apk/file products), `app_keys`
(`UNIQUE(product_id, key_value)`), `app_claims` (`ux_app_claims_owned` makes
app/file products single-purchase), `app_ad_rewards` (SSV dedupe, PK = AdMob
`transaction_id`), `app_idempotency` (`idem_key`, PK `(user_id, idem_key)`).

Apply both files in order, in phpMyAdmin or:

```powershell
mysql -u khctcfuv_ghost_premium -p khctcfuv_ghosst < database\mobile_app_schema.sql
mysql -u khctcfuv_ghost_premium -p khctcfuv_ghosst < database\mobile_app_data.sql
```

Both are pure additions (`CREATE TABLE IF NOT EXISTS` + `INSERT`). Re-running
the data file duplicates rows — it is a one-shot migration of the old D1 data.

## 2. Admin

There is no team/console UI. An account becomes admin with one statement:

```sql
UPDATE app_users SET is_admin = 1 WHERE email = 'you@example.com';
```

Sign out and back in afterwards — the app caches `isAdmin` for the session.
The **Admin** tab appears for admins only.

Coins are server-side only. To hand yourself some for testing:

```sql
UPDATE app_users SET coins = 100 WHERE email = 'you@example.com';
```

## 3. AdMob

Every unit ID lives in `lib/services/ad_service.dart` (`class AdUnits`).

| Format | Purpose | Where it shows |
|---|---|---|
| Rewarded | coins (SSV) | Earn tab — "Watch ad & earn coins" |
| Rewarded interstitial | coins (SSV) | Earn tab — "Instant ad & earn coins" |
| Interstitial | revenue only | every other tab switch, ≥45 s cooldown |
| Banner | revenue only | strip above the bottom nav |
| Native (medium) | revenue only | "Sponsored" card at the end of the Store |

App ID (already in the manifest): `ca-app-pub-7791552060229072~1855578469`.

1. **Rewarded units** (both): Ad unit → **Edit** → **Server-side
   verification** → set the bare URL
   `https://ghossthub.com/api/v1/ads/ssv` → **Verify URL** → **Save**.
   Reward amount = coins per ad (currently `10`); it comes back as
   `reward_amount` in the signed callback.
2. **Coins never arrive?** The API logs every rejection to PHP's error log
   (`SSV blocked: <reason>`). On Hostinger that is
   `public_html/logs/` / `error_log` in the File Manager. No log line at all
   ⇒ the callback URL is wrong in AdMob. A logged signature error ⇒ the
   verifier keys could not be fetched, not your URL.
3. **Unity Ads mediation fallback:** AdMob → Mediation → a rewarded group
   targeting both rewarded units, then Unity Ads as an ad source. Merely
   shipping `gma_mediation_unity` does not enable Unity inventory; startup
   logs must show `Unity Ads Adapter: ready`.
4. **Ad-blocker gate:** `lib/services/adblock_detector.dart` probes AdMob
   hosts with `$API_BASE_URL/products` as the control. 2 of 3 ad hosts
   blocked while the control answers = gate (`lib/screens/adblock_screen.dart`,
   third gate in `main.dart`, re-checked on resume). Fails open when offline or
   inconclusive; Private DNS is shown as context, never a standalone trigger.
5. **Coin-farm guards** (`api/lib/rewards.php`, enforced in `routes/ads.php`
   after the signature check, before the credit):
   - `ad_unit` must sit under our publisher id `ca-app-pub-7791552060229072/`.
     A callback signed for anyone else's ad unit is their ad, not ours.
   - 40 paid rewards per account per rolling 24 h, minimum 15 s apart. The
     30 s cooldown in the app is client-side and dies with an APK patch.
   - One reward per `transaction_id`; callbacks without one are keyed by their
     signed payload hash, so a replay cannot create a second credit.
   - A single reward is capped at 1000 coins, so a wrong AdMob reward setting
     cannot mint a balance.
   - Pacing is keyed on `sha256(lower(email))`, so deleting and re-registering
     the same address does not reset the daily cap.
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
      `https://ghossthub.com/api/v1/ads/ssv`.
- [ ] `api/` uploaded to `public_html/api/` and both SQL files applied to the
      production DB.
- [ ] `JWT_SECRET` in `api/config.php` changed from the placeholder.
- [ ] `CLOUDINARY_API_SECRET` set, so deleting a product also deletes its
      images.
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
| Every request `500 internal` | DB unreachable or `app_*` tables missing — check `api/config.php` credentials, then the error log |
| Coins never arrive after a real ad | No `SSV blocked` and no credit line in the error log ⇒ callback URL wrong in AdMob |
| `401` right after opening the app | Refresh token expired/revoked — sign in again |
| Admin tab missing | `app_users.is_admin = 0` for that account, or the app still holds the cached session (sign out/in) |
| Store shows no products | Create one in Admin, `active = 1` |
| Buy app → `Download not configured` | No `app_product_files` row for that product — re-save the link in the Admin edit dialog |
| Download stuck / `Could not resolve` | MediaFire link invalid or page changed — paste a fresh share link |
| APK won't install | `REQUEST_INSTALL_PACKAGES` missing from the manifest (play flavor) or "install unknown apps" disabled for Ghosst |
| Release: `Missing classes detected while running R8` | Copy the `-dontwarn` lines from `build/app/outputs/mapping/<variant>/missing_rules.txt` into `android/app/proguard-rules.pro` |
| Release: `Gradle build daemon disappeared` | `org.gradle.jvmargs` too big for the machine — 4G works on 12 GB Windows and 7 GB CI runners |

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
