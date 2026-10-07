# SETUP — Ghosst Keys (Flutter + Appwrite + AdMob SSV)

Backend on Appwrite project `6ac4baef0010879da982` (`https://sgp.cloud.appwrite.io/v1`).

**Flow:** admin stocks keys → users watch rewarded ads → Google calls our
`reward-ssv` function (signed callback) → coins credited → user spends coins →
`claim` function hands out the oldest available key.

Function IDs are referenced by the app as **`claim`** and **`reward-ssv`** —
create them with those exact `$id`s.

---

## 1. Project / platform settings

1. Appwrite Console → **Settings → Platforms → Add platform → Flutter app**:
   - Name: `ghosst`, Package name: `com.protech.ghosst`.
2. Platform scopes — make sure these are enabled (leave defaults if unsure):
   `account.read`, `account.write`, `databases.read`, `databases.write`,
   `functions.read`, `functions.write`.

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

Permissions: Read → **Users**; Create/Update/Delete → **Team: `admins`**.

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

Permissions: **none at collection level** — the function writes each document
with `read("user:<uid>")`, so users see only their own claims.

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

## 3. Team

**Auth → Teams → Create team** → ID/name: `admins`, then add your own user as
member. That's what unlocks the Admin tab and key/product write permissions.

## 4. Functions

> **Single-function variant (recommended):** everything below is now merged
> into ONE function with ID **`claim`** (`functions/claim/`, package
> `claim.tar.gz`). It routes internally: `?signature=...` → AdMob SSV,
> `{productId}` → license claim (debug simulate path removed). Deploy just
> `claim` with a **domain (HTTP)**, env var `COINS_PER_REWARD=10` (fallback),
> scopes `documents.read`/`documents.write`, Execute access = Any. AdMob
> callback URL = **`https://claim.sgp.appwrite.run/`** (bare — verify the URL
> *without* query parameters; AdMob's Verify button fails on `?...` URLs).
> The old two-function layout below (`functions/reward-ssv/`) is kept for
> reference only.

Both are dependency-free Node.js (they call the Appwrite REST API with the
ephemeral key, so no `node_modules`).

Zip them locally:

```powershell
Compress-Archive -Path functions\claim\*        -DestinationPath claim.zip -Force
Compress-Archive -Path functions\reward-ssv\*   -DestinationPath reward-ssv.zip -Force
```

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

1. Create an AdMob app + **Rewarded** ad unit. Set the reward item
   (e.g. `Coins`) and **amount = coins per ad** (e.g. `10`) — this value comes
   back as `reward_amount` in the signed callback.
2. Edit the ad unit → **Server-side verification** → enable, paste the
   **bare** callback URL (`https://claim.sgp.appwrite.run/`), click
   **Verify URL**, then **Use verified URL** → Save.
3. Until that's done the app uses Google's **test** rewarded unit
   (`ca-app-pub-3940256099942544/5224354917`) and a **test** AdMob app ID in
   `android/app/src/main/AndroidManifest.xml` — replace both before release.

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

## 7. Release checklist

- [ ] Real AdMob app ID in the manifest, real rewarded unit in
      `lib/services/ad_service.dart` (`rewardedAdUnitId`), SSV enabled with the
      **bare** production callback URL.
- [ ] `keys` collection readable **only** by `admins` team.
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

## Architecture notes / limits

- Coins are written **only** by `reward-ssv`; keys are assigned **only** by
  `claim`. A modded client can't mint either. Remaining trust boundary is
  AdMob's own callback authenticity (RS256 signature from Google).
- Coin deduction is read-modify-write inside one function execution — two
  truly simultaneous claims could race. At this scale it's fine; if it ever
  matters, move deduction to a queue or Appwrite's data-layer transaction.
- AdMob SSV can arrive seconds-to-minutes after the ad closes; the app waits
  ~45s and then tells the user the coins will land automatically.
