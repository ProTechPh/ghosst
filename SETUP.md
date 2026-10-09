# SETUP — Ghosst Keys (Flutter + Appwrite + AdMob SSV)

Backend on Appwrite project `6ac4baef0010879da982` (`https://sgp.cloud.appwrite.io/v1`).

**Flow:** admin stocks keys → users watch rewarded ads → Google calls our
`reward-ssv` function (signed callback) → coins credited → user spends coins →
`claim` function hands out the oldest available key (or, for **app/file
products**, the MediaFire download link).

**App store:** products can be `type = key` (license key), `apk` (installable
APK) or `file` (generic file). APK/file products are bought with the same coins
and deliver a MediaFire link instead of a key — see §2.1.

The app uses exactly one Appwrite function: **`claim`**. It handles product
claims, AdMob SSV rewards, and authenticated permanent account deletion. The
old **`reward-ssv`** folder is kept for source reference only; do not deploy it.

---

## 1. Project / platform settings

1. Appwrite Console → **Settings → Platforms → Add platform → Flutter app**:
   - Name: `ghosst-play`, Package name: `com.astrixtech.ghosst`.
   - Add a second platform for sideload releases: Name `ghosst-direct`,
     package name `com.astrixtech.ghosst.direct`.
2. Platform scopes — make sure these are enabled (leave defaults if unsure):
   `account.read`, `account.write`, `databases.read`, `databases.write`,
   `functions.read`, `functions.write`.
3. There are two Android flavors. `direct` keeps
   `REQUEST_INSTALL_PACKAGES` for its APK store. The `play` manifest explicitly
   removes that permission and hides all APK/file download paths. Neither
   flavor has an in-app updater; Google Play owns Play-build updates.

## 2. Database

**Databases → Create database** → ID: `ghosst`.

### Collection: `profiles`  (document `$id` = Appwrite user id)

| Attribute | Type | Required | Default | Notes |
|---|---|---|---|---|
| `coins` | integer | yes | 0 | min 0 |
| `displayName` | string(128) | no | | |

Permissions: **none at collection level.** Documents are created by our
functions with `read("user:<uid>")`, so users can read only their own profile.

### Collection: `products`

| Attribute | Type | Required | Default | Index |
|---|---|---|---|---|
| `name` | string(128) | yes | | key index `name` |
| `cost` | integer | yes | 50 | |
| `active` | boolean | yes | true | key index `active` |
| `description` | string(2000) | no | | shown on the product detail page |
| `images` | string(4096) | no | | JSON array of storage file ids |
| `youtubeUrl` | string(256) | no | | full YouTube watch/share URL |
| `type` | string(8) | no | `key` | `key` \| `apk` \| `file` |
| `version` | string(32) | no | | shown as a pill on app products |
| `fileSize` | string(32) | no | | free-text, e.g. `7.2 MB` |
| `durations` | string(4096) | no | | JSON array of `{label, cost}` duration options (key products) |

Permissions: Read → **Users**; Create/Update/Delete → **Team: `admins`**.

> **Create the three new columns before building.** The app only sends them
> when they differ from the default (this matches how optional columns already
> behave), but the claim function reads `product.type`, so the column must
> exist or every claim still falls back to a key.

> **Duration options** (added for key products with 1 Hour / 1 Day / 3 Days
> style pricing): `products.durations` holds the admin-defined options,
> `keys.duration` tags which pool a pasted key belongs to, and
> `claims.duration` records what the buyer picked. All three columns must
> exist **and the `claim` function must be redeployed** before duration
> claims work. Flat-price products (empty `durations`) behave exactly as
> before.

### Collection: `app_files`  (MediaFire links for app/file products)

Created for **§2.1 — the app store**. One document per downloadable product.

| Attribute | Type | Required | Default | Index |
|---|---|---|---|---|
| `productId` | string(36) | yes | | key index `productId` (unique per product) |
| `url` | string(1024) | yes | | MediaFire page **or** direct download URL |
| `quickkey` | string(64) | no | | MediaFire quickkey (Phase 2 API upload) |

Permissions: Read → **Team: `admins` only**; Create/Update/Delete →
**Team: `admins`**.

> ⚠️ **Read must be `admins` only.** This link is what the user is paying for —
> if regular users could list this collection they could grab it without coins.
> Users receive the URL only from the `claim` function after a successful
> purchase (written into their `claims` doc as `downloadUrl`).

### Storage bucket: `product-images`

**Storage → Create bucket** → ID: `product-images`.

| Setting | Value |
|---|---|
| File security | Off (bucket-level permissions) |
| Read | **Any** (previews must load for signed-out/regular users) |
| Create / Update / Delete | **Team: `admins`** |
| Allowed extensions | `jpg`, `jpeg`, `png`, `webp`, `gif` |
| Maximum file size | 5 MB |

The admin screen uploads product images here; the app builds public preview
URLs (`.../files/<id>/preview?project=...&width=...`). `Read = Any` is
required — with anything narrower, store images will not load.

### Collection: `keys`  (license keys)

| Attribute | Type | Required | Default | Index |
|---|---|---|---|---|
| `productId` | string(36) | yes | | key index `productId` |
| `key` | string(512) | yes | | |
| `status` | string(16) | yes | `available` | key index `status` |
| `claimedBy` | string(36) | no | | |
| `claimedAt` | datetime | no | | |
| `duration` | string(64) | no | | duration pool label (key products with options) |

Composite key index `product_status` on (`productId`, `status`) — required for
the claim query.

Permissions: Read → **Team: `admins` only**; Create/Update/Delete →
**Team: `admins`**. Regular users must never be able to list keys.

### Collection: `claims`

| Attribute | Type | Required | Default | Index |
|---|---|---|---|---|
| `userId` | string(36) | yes | | key index `userId` |
| `productId` | string(36) | yes | | |
| `productName` | string(128) | no | | |
| `keyId` | string(36) | yes | | |
| `keyText` | string(512) | yes | | |
| `cost` | integer | yes | 0 | |
| `createdAt` | datetime | yes | | |
| `downloadUrl` | string(1024) | no | | set for **app/file** purchases only |
| `duration` | string(64) | no | | duration label the buyer picked (key products) |

Permissions: **none at collection level** — the function writes each document
with `read("user:<uid>")`, so users see only their own claims.

> `keyText` doubles as the product type for app purchases (`apk` / `file`) and
> `keyId` falls back to the product id — the client uses a non-empty
> `downloadUrl` to tell an app purchase from a license key.

### Collection: `ad_rewards`  (SSV dedupe ledger)

| Attribute | Type | Required |
|---|---|---|
| `userId` | string(36) | yes |
| `reward` | integer | yes |
| `nonce` | string(128) | no |
| `adUnit` | string(128) | no |
| `eventTime` | string(64) | no |
| `createdAt` | datetime | yes |

Permissions: **none** (function only). Document id = the AdMob `nonce` —
replayed callbacks hit id-exists (409) and are ignored.

> The collection doubles as the **global mutation lock**: before touching
> any balance the function inserts a document with the fixed id `crit`
> (acquire) and deletes it afterwards (release); a crashed execution is
> taken over after 30s. Don't create documents with that id manually.

## 3. Team

**Auth → Teams → Create team** → ID/name: `admins`, then add your own user as
member. That's what unlocks the Admin tab and key/product write permissions.

## 4. Functions

### Claims, ad rewards, and account deletion

> Everything is merged into ONE function with ID **`claim`**
> (`functions/claim/`, package `claim.tar.gz`). It routes internally:
> `?signature=...` → AdMob SSV,
> `{productId}` → license claim **or app/file claim** (reads `product.type`;
> for `apk`/`file` it looks up `app_files`, deducts coins and returns
> `{ok, downloadUrl, type, cost}`),
> `{action: "deleteAccount", confirm: "DELETE"}` → authenticated permanent
> deletion, and `?yt=...` → YouTube embed HTML. Deploy just
> `claim` with a **domain (HTTP)**, env vars described below,
> scopes `documents.read`, `documents.write`, `users.read`, and `users.write`;
> Execute access = Any. The deletion route still requires the caller's valid
> user JWT. AdMob
> callback URL = **`https://claim.sgp.appwrite.run/`** (bare — verify the URL
> *without* query parameters; AdMob's Verify button fails on `?...` URLs).
> The old two-function layout below (`functions/reward-ssv/`) is kept for
> reference only.

It is dependency-free Node.js (it calls the Appwrite REST API with the
ephemeral key, so no `node_modules`).

Package them locally (**`.tar.gz`**, works on Windows 10+ `tar`):

```powershell
tar -czf claim.tar.gz -C functions/claim .
```

> Zip also works (`Compress-Archive -Path functions\claim\* -DestinationPath claim.zip -Force`),
> but `.tar.gz` is the Appwrite CLI convention — upload either as the deployment archive.

Create only **Functions → `claim`**, then in **Settings**:

| Setting | `claim` |
|---|---|
| Runtime | Node.js (latest) |
| Entrypoint | `index.js` |
| Trigger | **SDK + domain (HTTP)** |
| Execute access | **Any** (AdMob cannot authenticate; protected app routes validate JWT) |
| Timeout | 30s default |
| Scopes (ephemeral key) | `documents.read`, `documents.write`, `users.read`, `users.write` |
| Env vars | `COINS_PER_REWARD=10`, `BETA_BONUS_ENABLED=true`, `BETA_DAILY_COINS=5`, `BETA_TEST_REWARDS_ENABLED=true`, `BETA_TEST_COINS=5`, `BETA_TEST_COOLDOWN_SECONDS=30` |

`BETA_BONUS_ENABLED=true` enables the temporary no-fill fallback. It is
authenticated and limited server-side to one claim per Appwrite user per UTC
day. Set it to `false` when the beta ends; never replace this with a client-side
coin increment. `BETA_DAILY_COINS` is clamped by the function to 1–100.
For closed-beta test-ad builds, `BETA_TEST_REWARDS_ENABLED=true` credits each
completed test ad after a server-enforced cooldown. The amount is controlled by
`BETA_TEST_COINS` (1–100) and the cooldown by
`BETA_TEST_COOLDOWN_SECONDS` (10–3600). Disable both beta flags and reset beta
balances before promoting a live-ads bundle to Production.

Upload the zip under **Deployments → Create deployment** (build command:
default `npm install` is fine).

**`claim` domain:** open the function → **Domains** tab → copy the
generated URL (e.g. `https://claim.sgp.appwrite.run`). Use it **bare** as
the AdMob callback URL — AdMob's *Verify URL* button fails with an
"internal error" on URLs that contain `?...`; the bare URL verifies, and
the function still answers real SSV callbacks (AdMob appends the params)
with HTTP 200 `ok`.

## 5. AdMob

The app wires **all six AdMob formats** — every unit ID lives in
`lib/services/ad_service.dart` (class `AdUnits`):

| Format | Purpose | Where it shows | ID |
|---|---|---|---|
| Rewarded | coins (SSV) | Earn tab — "Watch ad & earn coins" | `AdUnits.rewarded` (**real**) |
| Rewarded interstitial | coins (SSV) | Earn tab — "Instant ad & earn coins" | `AdUnits.rewardedInterstitial` (**real**) |
| Interstitial | profit only | every other tab switch, ≥45 s cooldown | `AdUnits.interstitial` (**real**) |
| App open | profit only | once, right after the splash | `AdUnits.appOpen` (**real**) |
| Banner | profit only | strip above the bottom nav (all tabs) | `AdUnits.banner` (**real**) |
| Native (medium) | profit only | "Sponsored" card at the end of the Store list | `AdUnits.native` (**real**) |

App ID (already in the manifest): `ca-app-pub-7791552060229072~1855578469`.

1. **Rewarded (coins):** set the reward item (e.g. `Coins`) and **amount =
   coins per ad** (e.g. `10`) — this value comes back as `reward_amount` in
   the signed callback.
2. Edit the **Rewarded** unit → **Server-side verification** → enable, paste
   the **bare** callback URL (`https://claim.sgp.appwrite.run/`), click
   **Verify URL**, then **Use verified URL** → Save.
3. **Rewarded interstitial** is created with the same SSV treatment —
   `AdUnits.rewardedInterstitial` is wired with its real ID. The four passive
   units (Banner / Interstitial / App open / Native) need no SSV.
4. **Unity Ads mediation fallback:** in AdMob → Mediation, create a mediation
   group for Android rewarded inventory, target both Ghosst rewarded ad units,
   then add Unity Ads as an ad source with the Unity Game ID and placement ID.
   Complete Unity's bidding/waterfall partnership setup and mapping. Merely
   adding `gma_mediation_unity` to the app does not enable Unity inventory in
   AdMob. Confirm startup logs contain `Unity Ads Adapter: ready`; load-error
   waterfall logs should list a Unity adapter response.
5. The passive formats (banner, interstitial, app open, native) need **no
   SSV** — they earn you revenue only and never touch the coin balance.
6. **Ad-blocker gate:** ads pay for the app, so a device that filters them
   is locked out. `lib/services/adblock_detector.dart` probes three real
   AdMob hosts against the Appwrite endpoint as control — 2 of 3 blocked
   while the control answers = gate (`lib/screens/adblock_screen.dart`,
   third gate in `main.dart`, re-checked on app resume). Fails open when
   offline or inconclusive; Private DNS (`getPrivateDns` on the security
   channel) is shown as context only, never a standalone trigger.

## 6. Run & test

```powershell
flutter pub get
flutter run --flavor play
# or for the sideload-only feature set:
flutter run --flavor direct
# Release-mode QA with guaranteed-fill Google test ads (never publish this):
flutter run --release --flavor play --dart-define=USE_TEST_ADS=true
flutter build appbundle --release --flavor play
flutter build apk --release --flavor direct
```

1. Sign up → **Admin** tab appears only for the `admins` team member.
2. Admin: create a product (e.g. "Pro key", cost 20), paste keys (one per line)
   → **Add keys**.
3. For a fresh account there are no coins yet — give yourself coins in the
   console: `profiles` → your user-id document → `coins = 100`.
4. Earn for real: **Watch ad to earn coins** → after the ad closes the app
   polls your profile until Google's SSV callback lands (usually seconds;
   can take up to a minute — coins still arrive after a timeout message).
5. Store → **Claim** → key shown + copied → **My Keys**.
6. **App store test:** Admin → New product → type **APK** (or **File**) →
   paste a MediaFire link (page link like
   `https://www.mediafire.com/file/<key>/<name>/file` **or** a direct
   `https://downloadNN.mediafire.com/...` URL — both work) → **Add product**.
   Store → **Apps** tab → Buy & download → the download screen resolves the
   link, shows progress, then **Install** (APK) / **Open file** (file).

### 6.1 App store / MediaFire notes

- **Admin paste flow (current):** upload the file to MediaFire yourself
  (web or app), copy the share link, paste it in the Admin product form. The
  app resolves page links → direct link at download time (two-step fetch, no
  JS needed).
- **No MediaFire account required** to *download*; hosting still needs an
  uploader. Free MediaFire accounts are capped at ~50 GB/day of direct
  downloads, and direct links can rotate — page links are safer to store.
- **Phase 2 — API upload (not built yet):** to upload from inside the app,
  register an app id at mediafire.com → *My Account → Developers*, then add a
  new function (or route in `claim`) that calls
  `user/get_session_key` (email+password+app_id → session_token) →
  `file/get_upload_config` → POST upload → `upload/poll_upload` → quickkey →
  `file/get_links?link_type=direct_download`. Keep credentials **only** in
  function env vars (`MF_EMAIL`, `MF_PASSWORD`, `MF_APP_ID`) — never in the
  Flutter client. Store the resulting `quickkey` in `app_files`.

## 7. Release checklist

- [ ] Real AdMob app ID in the manifest, real unit IDs for **all six formats**
      in `lib/services/ad_service.dart` (`AdUnits`), and SSV enabled on **both
      rewarded units** with the **bare** production callback URL.
- [ ] `keys` collection readable **only** by `admins` team.
- [ ] `app_files` collection readable **only** by `admins` team.
- [ ] `products` has the `type` / `version` / `fileSize` columns and `claims`
      has `downloadUrl`.
- [ ] `claim` function redeployed (it must contain the app-claim route) and
      has `documents.read`, `documents.write`, `users.read`, and `users.write`
      scopes. Verify both a product claim and Profile → Delete account.
- [ ] Each published APK/file product has a working MediaFire link.
- [ ] Play upload uses the `N` from CI: every push to `main` auto-bumps
       `version: x.y.z+N` in `pubspec.yaml` and publishes release `vX.Y.Z+N`.
       Bump `x.y.z` by hand when the release needs a new feature version;
       Play Store is the only update channel and `N` must always increase.
- [ ] Use the correct GitHub Release asset: `live-ads.aab` for production Play,
      `closed-beta-test-ads.aab` for temporary closed testing,
      `release-live-ads.apk` for production sideload testing,
      `release-test-ads.apk` for release-mode QA, and `debug-test-ads.apk` for
      development. Upload only one AAB for each version code. Never promote a
      `test-ads` bundle to Production or distribute either test APK publicly.
- [ ] Product costs / reward amount reviewed.
- [ ] Upload the release's deobfuscation file to Play Console so crashes are
      readable: download `mapping.txt.gz` from the matching GitHub release
      `vX.Y.Z+N`, `gunzip` it, then **Play Console → your app → Testing →
      Internal testing → the release → App bundle explorer → version code →
      Upload deobfuscation file** (`mapping.txt`). R8 is on for release
      builds (`android/app/build.gradle.kts`), so Play's raw stack traces are
      obfuscated without it. Keep the mapping for every shipped version code —
      it must match the exact bundle.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Claim: `Function not configured (missing scopes)` | Function Scopes missing `databases.read`/`databases.write` |
| Claim: `Not signed in` inside function | User session expired, or execute access/scopes wrong |
| Claim: `Missing index` | Collection index (esp. `product_status`) not created |
| Admin tab missing | User not in team `admins` |
| Coins never arrive after a real ad | Check `reward-ssv` **Executions** log: if no execution at all → callback URL wrong; if `bad signature`/`stale` → clock/cert issue; if `missing user_id` → ad loaded without SSV options |
| Rewarded ad says no inventory | First run a debug build (automatic Google sample ads) or release QA with `USE_TEST_ADS=true`. If test ads load, the SDK is healthy: activate the AdMob mediation group, map both rewarded units to Unity, verify the Unity account/placement is live, and inspect the per-adapter waterfall logs. New production units can also take time to begin serving. |
| `Permission denied` listing keys as admin | Team membership/permissions on `keys` collection |
| Store shows no products | Create one in Admin tab (or console), `active = true` |
| Buy app → `Download not configured` | No `app_files` doc for that product (or blank `url`) — re-save the link in the Admin edit dialog |
| Buy app → `Collection not found` | `app_files` collection / `products.type` column not created yet, or `claim` not redeployed |
| Download stuck / `Could not resolve` | MediaFire link invalid or page changed — paste a fresh share link; direct `downloadNN.mediafire.com` links usually rotate and expire |
| APK won't install | `REQUEST_INSTALL_PACKAGES` missing from the manifest, or "install unknown apps" disabled for Ghosst in Android settings |
| Release build: `Missing classes detected while running R8` | Flutter references Play Core split-install classes it doesn't ship — copy the `-dontwarn` lines from `build/app/outputs/mapping/<variant>/missing_rules.txt` into `android/app/proguard-rules.pro` |
| Release build: `Gradle build daemon disappeared unexpectedly` / `hs_err_pid*.log` says out of RAM | `org.gradle.jvmargs` in `android/gradle.properties` too big for the machine (R8 needs real headroom) — lower `-Xmx` (4G works on 12 GB Windows and 7 GB CI runners) |

## Architecture notes / limits

- Coins are written **only** by `reward-ssv`; keys are assigned **only** by
  `claim`. A modded client can't mint either. Remaining trust boundary is
  AdMob's own callback authenticity (RS256 signature from Google). Same for
  downloads: MediaFire links live in `app_files` (admin-only) and are handed
  out **only** by `claim` after the coin deduction — a modded client can't
  read them.
- Coin deduction is read-modify-write inside one function execution — two
  truly simultaneous requests used to race (both passing the balance check
  from the same snapshot = two keys for one payment, or a reward
  overwriting a just-spent balance). **Fixed:** every `coins`/stock
  mutation now runs behind a global critical-section lock (the `crit`
  document in `ad_rewards` — acquire = insert, release = delete, 30s stale
  takeover). A modded / memory-editing client can only fire requests
  faster; serialized, that gains it nothing.
- AdMob SSV can arrive seconds-to-minutes after the ad closes; the app waits
  ~45s and then tells the user the coins will land automatically.
