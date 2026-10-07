# SETUP — Ghosst Keys (Flutter + Appwrite + AdMob SSV)

Backend on Appwrite project `6ac4baef0010879da982` (`https://sgp.cloud.appwrite.io/v1`).

**Flow:** admin stocks keys → users watch rewarded ads → Google calls our
`reward-ssv` function (signed callback) → coins credited → user spends coins →
`claim` function hands out the oldest available key (or, for **app/file
products**, the MediaFire download link).

**App store:** products can be `type = key` (license key), `apk` (installable
APK) or `file` (generic file). APK/file products are bought with the same coins
and deliver a MediaFire link instead of a key — see §2.1.

Function IDs are referenced by the app as **`claim`** and **`reward-ssv`** —
create them with those exact `$id`s.

---

## 1. Project / platform settings

1. Appwrite Console → **Settings → Platforms → Add platform → Flutter app**:
   - Name: `ghosst`, Package name: `com.protech.ghosst`.
2. Platform scopes — make sure these are enabled (leave defaults if unsure):
   `account.read`, `account.write`, `databases.read`, `databases.write`,
   `functions.read`, `functions.write`.
3. `android/app/src/main/AndroidManifest.xml` also declares
   `android.permission.REQUEST_INSTALL_PACKAGES` (so the download screen can
   prompt **Install** for APKs) plus a `<queries>` entry for the
   `application/vnd.android.package-archive` MIME type.

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

### Collection: `updates`  (forced-update announcements)

| Attribute | Type | Required |
|---|---|---|
| `versionCode` | integer | yes |
| `versionName` | string(32) | no |
| `url` | string(2048) | yes |
| `message` | string(512) | no |
| `active` | boolean | yes |

Permissions: **Read → All users**, **Create / Delete → Team admins**.

At launch the app reads the active announcement; when `versionCode` is
higher than its own build number the whole UI is replaced by the blocking
update gate (in-app download with progress → system install prompt — there
is no dismiss; cancelling the install sheet lands back on the gate).
Each publish retires the previous announcement, so exactly one `active`
doc should exist. There is no publish UI in the app anymore — CI is the
publisher (below), or insert/delete `updates` docs from the Appwrite
console if you ever need to do it by hand.

**CI publishes this automatically.** Every push to `main` that ships a
release runs `.github/workflows/release.yml` → *Open forced-update gate*:
it deletes the previous announcement and posts the new build number with
the fixed download URL
`https://github.com/ProTechPh/ghosst/releases/latest/download/Ghosst.apk`
(the repo is public, so the app downloads it anonymously). One-time setup:

1. **Appwrite → Settings → API keys → Create key** (e.g. `github-release`)
   scoped to **Databases → `updates` → documents: read, create, delete**
   (or the umbrella `documents.read` / `documents.create` /
   `documents.delete` scopes if collection-level scoping isn't available).
2. **GitHub → repo Settings → Secrets and variables → Actions → New
   repository secret** → name `APPWRITE_API_KEY`, value = that key.
3. Optional secret `UPDATE_URL` — overrides the download link (e.g. a
   MediaFire page) if you don't want to serve the APK from GitHub.

Until the secret exists the step is skipped (the release itself still
succeeds) and no gate opens — insert an `updates` doc from the Appwrite
console if you need to force an update before the secret is set.

## 3. Team

**Auth → Teams → Create team** → ID/name: `admins`, then add your own user as
member. That's what unlocks the Admin tab and key/product write permissions.

## 4. Functions

> **Single-function variant (recommended):** everything below is now merged
> into ONE function with ID **`claim`** (`functions/claim/`, package
> `claim.tar.gz`). It routes internally: `?signature=...` → AdMob SSV,
> `{productId}` → license claim **or app/file claim** (reads `product.type`;
> for `apk`/`file` it looks up `app_files`, deducts coins and returns
> `{ok, downloadUrl, type, cost}`), `?yt=...` → YouTube embed HTML.
> Deploy just
> `claim` with a **domain (HTTP)**, env var `COINS_PER_REWARD=10` (fallback),
> scopes `documents.read`/`documents.write`, Execute access = Any. AdMob
> callback URL = **`https://claim.sgp.appwrite.run/`** (bare — verify the URL
> *without* query parameters; AdMob's Verify button fails on `?...` URLs).
> The old two-function layout below (`functions/reward-ssv/`) is kept for
> reference only.

Both are dependency-free Node.js (they call the Appwrite REST API with the
ephemeral key, so no `node_modules`).

Package them locally (**`.tar.gz`**, works on Windows 10+ `tar`):

```powershell
tar -czf claim.tar.gz -C functions/claim .
# legacy/reference only:
tar -czf reward-ssv.tar.gz -C functions/reward-ssv .
```

> Zip also works (`Compress-Archive -Path functions\claim\* -DestinationPath claim.zip -Force`),
> but `.tar.gz` is the Appwrite CLI convention — upload either as the deployment archive.

For **each** function: **Functions → Create function** with the exact ID
(`claim` / `reward-ssv`), then in **Settings**:

| Setting | `claim` | `reward-ssv` |
|---|---|---|
| Runtime | Node.js (latest) | Node.js (latest) |
| Entrypoint | `index.js` | `index.js` |
| Trigger | **SDK + domain (HTTP)** | **HTTP** |
| Execute access | **Any** (function itself checks the JWT) | **Any** (Google can't authenticate) |
| Timeout | 30s default | 30s default |
| Scopes (ephemeral key) | `documents.read`, `documents.write` | `databases.read`, `databases.write` |
| Env vars | `COINS_PER_REWARD` = `10` (fallback) | – (legacy, not deployed) |

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
4. The passive formats (banner, interstitial, app open, native) need **no
   SSV** — they earn you revenue only and never touch the coin balance.

## 6. Run & test

```powershell
flutter pub get
flutter run
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
      each published APK/file product has a working MediaFire link.
- [ ] `updates` collection created (Read → users; Create/Delete → admins)
      before any release that should open the forced-update gate.
- [ ] Repo secret `APPWRITE_API_KEY` set, so releases **auto-open** the
      forced-update gate (without it CI skips the gate step — insert the
      `updates` doc from the Appwrite console instead).
- [ ] Product costs / reward amount reviewed.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Claim: `Function not configured (missing scopes)` | Function Scopes missing `databases.read`/`databases.write` |
| Claim: `Not signed in` inside function | User session expired, or execute access/scopes wrong |
| Claim: `Missing index` | Collection index (esp. `product_status`) not created |
| Admin tab missing | User not in team `admins` |
| Coins never arrive after a real ad | Check `reward-ssv` **Executions** log: if no execution at all → callback URL wrong; if `bad signature`/`stale` → clock/cert issue; if `missing user_id` → ad loaded without SSV options |
| `Permission denied` listing keys as admin | Team membership/permissions on `keys` collection |
| Store shows no products | Create one in Admin tab (or console), `active = true` |
| Buy app → `Download not configured` | No `app_files` doc for that product (or blank `url`) — re-save the link in the Admin edit dialog |
| Buy app → `Collection not found` | `app_files` collection / `products.type` column not created yet, or `claim` not redeployed |
| Download stuck / `Could not resolve` | MediaFire link invalid or page changed — paste a fresh share link; direct `downloadNN.mediafire.com` links usually rotate and expire |
| APK won't install | `REQUEST_INSTALL_PACKAGES` missing from the manifest, or "install unknown apps" disabled for Ghosst in Android settings |

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
