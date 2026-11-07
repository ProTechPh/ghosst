# World Chat on Firebase (backend-UUID identity) — Design

Date: 2026-11-07 · Status: approach approved in conversation (custom tokens); doc pending sign-off

## Intent & why

One global chat room ("world chat") for all signed-in Ghosst users, backed by Firestore.
Identity is the backend's user UUID (`app_users.id`) — never a Firebase account. The PHP
API mints short-lived Firebase **custom tokens** that embed that UUID (plus an `admin`
claim), the app signs in with one invisible call, and Firestore rules prove who is
writing. No Firebase Auth UI, no provider sign-in, no new login for users.

Why not open rules: the app is a coin economy with admin announcements. The Firebase
config in the APK is public by design; open rules would let anyone with it post as
anyone (fake-admin scams) and spam via REST. Verified senders are the smallest honest
mechanism.

## Goals

- Single global chat; every signed-in user reads/writes; live updates.
- Sender = backend UUID; display name and a real (claim-enforced) ADMIN badge render.
- Works on both flavors — `android/app/google-services.json` already covers
  `com.astrixtech.ghosst` and `com.astrixtech.ghosst.direct`; gms plugin already applied.
- Account deletion keeps the PII promise: names scrubbed from chat, best-effort, logged.

## Non-goals (v1)

- Replies/threads, images, typing indicators, unread counts, chat push notifications.
- Moderation UI (delete/ban), profanity filter, server-side rate limiting (client
  cooldown only — see Known limits), message retention/TTL.

## Anti-goals

- No client-supplied identity trusted by rules (no open Firestore).
- No user-facing Firebase Auth and **no Anonymous provider** — anonymous sessions can
  be minted from the public config via REST, which would reopen the spam door.
- Nothing writes coins/keys/products from the client (unchanged).

## Constraints (from the repo)

- Gates are `flutter analyze` + `flutter test` only (CI pins Flutter 3.47.6). Tests have
  no network and mock platform channels → Firebase must be fully inert in tests.
- All app network access lives in `lib/services/worker_backend.dart` — the chat
  sign-in token fetch goes there too.
- API: plain PHP 8, no composer, upload-deployed; secrets in `config.php` with
  `getenv` overrides; `lib/auth.php` already hand-rolls HS256 JWT → we hand-roll the
  RS256 custom token the same way (OpenSSL, no dependency).
- `HomeShell` keeps every tab page alive in an `IndexedStack` → the chat page must
  mount in widget tests without touching a platform channel.
- Pill nav today: Store, Earn, Purchases, News (+ Admin). Chat becomes the 5th slot
  (6th for admin); unselected slots collapse to icons, fits 360dp.
- Firebase project exists: `ghosst-6f23e`; google-services.json + gms plugin already
  wired → Android auto-init: `Firebase.initializeApp()` with no arguments (confirmed
  against firebase_core docs). No `firebase_options.dart`, no flutterfire CLI step.
- `DELETE /v1/account` anonymises the user row; `docs/*.html` promises real PII
  deletion — a new PII store (chat names) must be scrubbed too.

## Approaches considered

1. **Open rules, client passes uid** — zero PHP. Rejected: config is extractable;
   anyone can write as anyone (fake-admin scams) and spam via REST.
2. **Anonymous Firebase Auth + client uid** — rejected: random Firebase uid, rules
   can't tie it to the backend UUID; enabling Anonymous reopens config-only sessions.
3. **Custom tokens minted by the PHP backend (chosen)** — backend already owns
   identity; mints a 1h RS256 JWT (`uid` = backend UUID, `claims.admin` when admin)
   signed with a Firebase service-account key; app calls `signInWithCustomToken` once
   per session; rules enforce sender and admin badge. Forging identity now requires
   stealing the SA key — same protection level as `CLOUDINARY_API_SECRET` already in
   `config.php`. ~80 lines of PHP.
- **Firestore over Realtime DB** — rules can check claims/fields, server timestamps,
   cheap snapshot listeners; single-field `ts` index is automatic.

## How (decided)

### Data model

Collection `world_chat`, one doc per message, immutable (no client update/delete):

```
{ uid: string, name: string ≤40, text: string 1..500, admin: bool, ts: serverTimestamp,
  replyName: string ≤40 (optional), replyText: string ≤200 (optional) }
```

Query: `orderBy('ts', desc) limit 50`, live snapshot stream.

**Name rule (decided):** `name` = trimmed `displayName` when non-empty, else
`Anon-<first 6 of uid>` — stable, unique-ish, no PII. The sign-up name is optional and
there is no rename route, so unnamed users need a non-PII fallback; **email is never
written to Firestore** (all signed-in users can read every message). Blank `name`
occurs only as the scrub output and renders as "Deleted user".

### Firestore rules

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /world_chat/{message} {
      allow read: if request.auth != null;
      allow create: if request.auth != null
        && request.resource.data.uid == request.auth.uid
        && request.resource.data.name is string
        && request.resource.data.name.size() <= 40
        && request.resource.data.text is string
        && request.resource.data.text.size() > 0
        && request.resource.data.text.size() <= 500
        && request.resource.data.text.matches('.*\\S.*')
        && request.resource.data.admin == (request.auth.token.admin == true)
        && request.auth.token.muted == false
        && request.resource.data.ts == request.time
        && (!('replyName' in request.resource.data)
          || (request.resource.data.replyName is string
            && request.resource.data.replyName.size() <= 40
            && request.resource.data.replyText is string
            && request.resource.data.replyText.size() <= 200))
        && request.resource.data.keys().hasOnly(['uid', 'name', 'text', 'ts', 'admin', 'replyName', 'replyText']);
      allow update, delete: if false;
    }
  }
}
```

### PHP API (`api/`)

- `config.php`: `FIREBASE_PROJECT_ID` (default `ghosst-6f23e`), `FIREBASE_SA_EMAIL`,
  `FIREBASE_SA_KEY` (base64 of the PEM, so an env var survives newlines). Blank SA
  config = feature off, same pattern as Cloudinary.
- `lib/firebase.php`:
  - `firebase_custom_token(string $uid, bool $isAdmin): string` — RS256 JWT exactly
    per Firebase docs: `iss`/`sub` = SA email, `aud =
    https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit`,
    `iat`, `exp` = iat+3600 (the max), `uid`, `claims {admin: true|false,
    muted: true|false}` — both claims are always present (absent claim =
    rules error on `request.auth.token.admin`/`muted`, denying writes).
    (`admin` is not a reserved claim). Signs with `openssl_sign` + `b64url_encode`,
    mirroring `sign_access_token()`.
  - `firebase_scrub_chat(string $uid): void` — SA-key OAuth2 token (scope
    `https://www.googleapis.com/auth/datastore`, JWT-to-token exchange via curl,
    following `lib/push.php`'s curl pattern) → Firestore REST `runQuery` for the
    user's messages → `commit` batch setting `name = ''`, `admin = false`.
    Best-effort: failures `log_line`'d, never throw.
- `routes/account.php`: `account_firebase_token` → `{ok, token}`; 503 `chat_disabled`
  when SA config is blank. Registered in `index.php` ROUTES:
  `['GET', '#^/v1/firebase/token$#', 'account_firebase_token', 'required']`.
- `account_remove`: after the MySQL commit, `if (firebase_enabled())
  firebase_scrub_chat($uid);` — scrub failure can never roll back deletion.

### Flutter

- `pubspec.yaml`: `firebase_core`, `firebase_auth`, `cloud_firestore` (latest stables
  at implementation time).
- `main.dart`: `unawaited(ChatService.init())` beside `Push.init()`; new page
  `ChatScreen` + `_NavItem` (chat bubble icons, label "Chat") after News; signing out
  also signs out of Firebase.
- `lib/services/chat_service.dart` (static class, `Backend` style):
  - `init()` — `Firebase.initializeApp()` no-arg; any failure → `ready = false`, chat
    tab shows "Chat unavailable". Never throws into the app (fail-open like the gates).
    In widget tests `main()` never runs → `ready = false` → inert fallback UI.
  - `ensureSignedIn()` — lazily on first chat use: `Backend.firebaseToken()` →
    `signInWithCustomToken`. If cached Firebase user's `admin` claim no longer matches
    `Backend.isAdmin()`, re-mint and re-sign-in (self-heals role changes).
  - `messages()` — snapshot stream mapped to a small `ChatMessage` model.
  - `send(text)` — trim, 1..500 chars, 5s cooldown; writes
    `{uid, name, text, admin, ts: FieldValue.serverTimestamp()}`.
- `lib/services/worker_backend.dart`: `firebaseToken()` → `GET /v1/firebase/token`.
- `lib/screens/chat_screen.dart`: embedded tab page using `premium.dart` primitives
  and `theme.dart` tokens (visual language of `AnnouncementsScreen`), reversed message
  list, input bar, ADMIN chip, "Deleted user" for blank names. Firestore's local cache
  gives offline queueing/replay for free.

### Tests (new, no network)

- `ChatService.send` validation + cooldown — pure Dart, injected clock/service.
- `ChatScreen` renders fallback when not ready, and renders messages from an injected
  fake service (same injection style as `AdblockDetector.runCheck`).

## Privacy & compliance edits (in scope, owner reviews wording)

`docs/index.html` currently states Firebase/OneSignal receives *"no email, account ID,
coin balance, or purchase data"* — world chat sends the account UUID, display name
(or Anon- fallback), and message text to Firestore, so that sentence must change:
draft — "Firebase receives your account ID and display name (or an anonymous handle)
to deliver world chat messages; message text is stored there. No email, coin balance,
or purchase data is sent to Firebase."

`docs/delete-account.html` "What is deleted" gains one line — draft: "World chat
messages are kept but your name on them is blanked (best-effort at deletion)."

Play Data Safety form (owner submits): declare account ID + user-generated content
shared with Firebase.

## Rollout order (decided — tab is always visible, fallback handles the gap)

Every push to `main` auto-publishes a release and the API deploys by manual upload, so:
1. Implement on a branch.
2. Owner: Firebase console setup (below) + upload `api/` to Hostinger.
3. Merge to `main`.

If a build reaches users before step 2, the Chat tab shows "Chat unavailable" — an
acceptable state for hours, not weeks. Hiding the tab until the backend confirms chat
is on would add client code for a one-time gap; not worth it (veto if you disagree).

## Setup (owner, one-time, Firebase console)

1. Firestore → Create database (production mode; region any — `asia-southeast1` is
   closest to PH) → paste the rules above. If the project already has rules (it was
   created for OneSignal/FCM), **merge** the `world_chat` match block into them
   instead of replacing the file.
2. No sign-in providers needed for custom tokens; do **not** enable Anonymous.
   Verify sign-in once after deploy (send a test message).
3. Project settings → Service accounts → Generate new private key (JSON) → set
   `GHOSST_FIREBASE_SA_EMAIL` + `GHOSST_FIREBASE_SA_KEY` (base64 of the PEM) as env
   vars on Hostinger, or paste into `config.php` defaults. Give the SA minimal IAM:
   Firebase Authentication Admin + Cloud Datastore User.
4. Upload `api/` per `api/README.md`.

## Known limits (deliberate)

- A user can spoof their own `name` (rules can't verify names without a users
  collection); the admin badge — the scam-relevant part — is claim-enforced.
- No server-side rate limit: a real account can spam via REST; the 5s cooldown is
  client-side only. `shortcut: cooldown is client-side only, add App Check + Cloud
  Function pacing when spam appears`
- No message TTL; the collection grows. Clean up via console or a scheduled job later.
- Firestore Spark free tier assumed (50k reads / 20k writes daily) — fine at current
  scale; revisit if DAU grows.
- Scrub is best-effort: if Hostinger can't reach Firestore during deletion, the names
  persist until a manual cleanup (logged as `Scrub failed` in the PHP error log).

## Left to the builder

- Exact package versions at `flutter pub get` (latest stables); any R8/proguard notes
  FlutterFire requires.
- PHP curl details: mirror `lib/push.php`'s request/error handling for the OAuth
  exchange and Firestore REST calls.
- `ChatMessage` model location: keep it inside `chat_service.dart` unless screens
  need it elsewhere; don't grow `models.dart` for chat-only types.
