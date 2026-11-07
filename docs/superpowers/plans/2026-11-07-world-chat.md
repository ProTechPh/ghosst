# World Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One global chat tab backed by Firestore, where sender identity is the backend UUID carried in a PHP-minted Firebase custom token (no Firebase Auth UI, no Anonymous provider).

**Architecture:** PHP API mints 1-hour RS256 custom tokens (`uid` = `app_users.id`, `claims.admin` for admins) from a service-account key in `config.php`; the app calls `signInWithCustomToken` once per chat session; Firestore rules enforce sender identity, field shape, and the admin badge. Account deletion best-effort scrubs the user's chat names via the Firestore REST API.

**Tech Stack:** Flutter (firebase_core, firebase_auth, cloud_firestore), PHP 8 (OpenSSL + curl, no composer), Firestore.

**Spec:** `docs/superpowers/specs/2026-11-07-world-chat-design.md` (approved 2026-11-07) — the plan argues from it; executors read both.

## Global Constraints

- Network access lives only in `lib/services/worker_backend.dart` — screens never call HTTP directly.
- Email is never written to Firestore; the account UUID is the only identifier stored per message.
- `flutter analyze` must report no issues (the only lint gate); `flutter test` must pass fully with no network and no real platform-channel calls — Firebase must be inert in tests (widget tests never ran `main()`, so `ChatService.ready` defaults false and only a fallback renders).
- Builds require a flavor: `flutter build apk --release --flavor play --dart-define=USE_TEST_ADS=true`; bare `flutter build` fails by design.
- Do not bump `version:` in `pubspec.yaml` by hand — CI auto-bumps on push to `main`, and every push to `main` auto-publishes a release. All work stays on the current `redesign` branch; **do not push**.
- API is plain PHP 8, no composer: hand-rolled JWT signing (reuse `b64url_encode`/`b64url_decode` from `api/lib/auth.php`), curl in the `api/lib/push.php` style (CONNECTTIMEOUT 3 / TIMEOUT 5, `error_log` on failure, never throw where the caller treats it as fire-and-forget).
- Local tooling: PHP 8.5.12 CLI available (`php -l`, `php -r`); **no local MySQL** — PHP smoke tests must not need the database.
- Message limits (mirror of the Firestore rules): text trimmed, 1–500 chars; name ≤ 40 chars; send cooldown 5 s; query last 50 by `ts` desc.
- Values pinned by the spec: `FIREBASE_PROJECT_ID` default `ghosst-6f23e`; custom-token `aud` = `https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit`; token TTL 3600 s; scrub writes `name=''`, `admin=false`, capped at 300 docs; fallback name `Anon-<first 6 of uid>`; blank name renders "Deleted user".

## Review Focus

1. **Whitespace-only or >500-char text** from a rapid typer or modified client → rejected client-side before any write, rules reject server-side → pinned in Task 4 (`validate` tests).
2. **Blank `name`** (scrub output of a deleted user) → renders "Deleted user", never an empty row → pinned in Task 5 (fake stream test).
3. **Unnamed live user** (optional display name at sign-up) → posts as `Anon-<uid6>`, never their email → pinned in Task 4 (`fallbackName` tests).
4. **Firebase unavailable** (init failure, offline, or API returns 503 `chat_disabled`) → chat tab shows "Chat unavailable"; the app never crashes and no other tab is affected → pinned in Task 5 (fake client `ready=false` test).
5. **Rapid double-tap send** → second send within the cooldown is rejected locally, no duplicate write → pinned in Task 4 (`cooldownPassed` tests).

---

### Task 1: PHP — custom-token minting (`lib/firebase.php` + config)

**Files:**
- Modify: `api/config.php` (after the Cloudinary block, ~line 33)
- Create: `api/lib/firebase.php`
- Modify: `api/index.php` (require block, after `lib/push.php` line 22)

**Interfaces:**
- Consumes: `b64url_encode()`, `b64url_decode()` from `api/lib/auth.php`.
- Produces (used by Tasks 2–3):
  - `firebase_enabled(): bool` — true only when `FIREBASE_SA_EMAIL` and `FIREBASE_SA_KEY` are non-empty.
  - `firebase_custom_token(string $uid, bool $isAdmin): string` — RS256 JWT; throws `RuntimeException` if disabled/unconfigured (callers check `firebase_enabled()` first).
  - `firebase_scrub_chat(string $uid): void` — added fully in Task 3; this task creates the file with the two functions above only.

- [ ] **Step 1: Add config defines to `api/config.php`**

After the Cloudinary block, same `getenv ?: default` pattern:

```php
/** Firebase world chat. Blank service account = feature off. */
define('FIREBASE_PROJECT_ID', getenv('GHOSST_FIREBASE_PROJECT_ID') ?: 'ghosst-6f23e');
define('FIREBASE_SA_EMAIL', getenv('GHOSST_FIREBASE_SA_EMAIL') ?: '');
define('FIREBASE_SA_KEY', getenv('GHOSST_FIREBASE_SA_KEY') ?: ''); // base64 ng PEM
```

- [ ] **Step 2: Write `api/lib/firebase.php`**

Style of `lib/auth.php` (`declare(strict_types=1)`, no classes, Taglish doc comments). Exact token claims per the Firebase docs (the algorithm):

```php
function firebase_custom_token(string $uid, bool $isAdmin): string
{
    $now = time();
    $claims = [
        'iss' => FIREBASE_SA_EMAIL,
        'sub' => FIREBASE_SA_EMAIL,
        'aud' => 'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
        'iat' => $now,
        'exp' => $now + 3600, // max allowed
        'uid' => $uid,
    ];
    if ($isAdmin) $claims['claims'] = ['admin' => true]; // 'admin' is not reserved

    $head = b64url_encode(json_encode(['alg' => 'RS256', 'typ' => 'JWT']));
    $body = b64url_encode(json_encode($claims));
    $key = openssl_pkey_get_private(base64_decode(FIREBASE_SA_KEY));
    if ($key === false) throw new RuntimeException('bad FIREBASE_SA_KEY');
    $ok = openssl_sign($head . '.' . $body, $sig, $key, OPENSSL_ALGO_SHA256);
    if (!$ok) throw new RuntimeException('openssl_sign failed');
    return $head . '.' . $body . '.' . b64url_encode($sig);
}
```

Add `require __DIR__ . '/lib/firebase.php';` in `api/index.php` after the `lib/push.php` line.

- [ ] **Step 3: Self-check the token structurally (no secrets, no DB)**

Run from repo root (single line; asserts 3 parts, claims, and an RS256 signature that verifies against the generated key):

```powershell
php -r "define('FIREBASE_SA_EMAIL','t@x.iam.gserviceaccount.com'); define('FIREBASE_PROJECT_ID','ghosst-6f23e'); $k=openssl_pkey_new(['private_key_bits'=>2048]); openssl_pkey_export($k,$pem); define('FIREBASE_SA_KEY',base64_encode($pem)); require 'api/lib/auth.php'; require 'api/lib/firebase.php'; $t=firebase_custom_token('uid-123',true); $p=explode('.',$t); $c=json_decode(b64url_decode($p[1]),true); $v=openssl_verify($p[0].'.'.$p[1],b64url_decode($p[2]),$k,OPENSSL_ALGO_SHA256); echo (count($p)===3 && $c['uid']==='uid-123' && $c['claims']['admin']===true && $c['aud']==='https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit' && $v===1) ? 'TOKEN OK' : 'TOKEN BAD';"
```

Expected: `TOKEN OK`.

- [ ] **Step 4: Lint and commit**

Run: `php -l api/lib/firebase.php` and `php -l api/config.php` → `No syntax errors`.

```bash
git add api/config.php api/lib/firebase.php api/index.php
git commit -m "feat(api): mint Firebase custom tokens from the service account"
```

### Task 2: PHP — `GET /v1/firebase/token` route

**Files:**
- Modify: `api/index.php` (ROUTES table, in the account group after the `/v1/account` line 37)
- Modify: `api/routes/account.php` (after `account_me`, ~line 23)

**Interfaces:**
- Consumes: `firebase_enabled()`, `firebase_custom_token()` from Task 1; `$ctx['user']['id']` and `$ctx['user']['isAdmin']` set by `require_user()`.
- Produces: endpoint returning `{'ok': true, 'token': '<jwt>'}`; 503 `chat_disabled` `ApiError` when unconfigured.

- [ ] **Step 1: Register the route in `api/index.php` ROUTES**

```php
['GET',    '#^/v1/firebase/token$#',                   'account_firebase_token',  'required'],
```

- [ ] **Step 2: Add the handler in `api/routes/account.php`**

```php
/** Custom token para sa world chat sign-in (uid = backend UUID). */
function account_firebase_token(array $ctx): array
{
    if (!firebase_enabled()) {
        throw new ApiError(503, 'chat_disabled', 'World chat is not configured');
    }
    return [
        'ok'    => true,
        'token' => firebase_custom_token($ctx['user']['id'], $ctx['user']['isAdmin']),
    ];
}
```

- [ ] **Step 3: Smoke the router without a DB**

Run in one terminal: `php -S 127.0.0.1:8099 -t api api/index.php` (repo root, background).
Then: `curl -s -i http://127.0.0.1:8099/v1/firebase/token -H "Authorization: Bearer x"`.
Expected: HTTP 401 with `"code":"unauthorized"` (proves the route matches — a miss returns 404 `not_found`). Stop the server afterwards.

- [ ] **Step 4: Lint and commit**

Run: `php -l api/routes/account.php` and `php -l api/index.php` → no syntax errors.

```bash
git add api/index.php api/routes/account.php
git commit -m "feat(api): GET /v1/firebase/token mints the chat custom token"
```

### Task 3: PHP — deletion scrub + README (env vars, Firestore rules)

**Files:**
- Modify: `api/lib/firebase.php` (append scrub helpers)
- Modify: `api/routes/account.php:77-83` (after the `$pdo->commit();` in `account_remove`)
- Modify: `api/README.md`

**Interfaces:**
- Consumes: `FIREBASE_PROJECT_ID`, `FIREBASE_SA_EMAIL`, `FIREBASE_SA_KEY`; curl pattern from `api/lib/push.php`.
- Produces: `firebase_scrub_chat(string $uid): void` (never throws; `error_log`s failures) — called by `account_remove`.

- [ ] **Step 1: Append scrub helpers to `api/lib/firebase.php`**

Two private helpers + one public function, push.php curl style (timeouts, `error_log`, never throw):
  - `_firebase_access_token(): string` — service-account OAuth2: RS256 JWT (`iss`=SA email, `scope`=`https://www.googleapis.com/auth/datastore`, `aud`=`https://oauth2.googleapis.com/token`, `iat`/`exp` 3600) signed with the same key, POSTed to the token endpoint; returns `access_token`. Cache in a static var.
  - `_firestore_post(string $path, string $json): array` — POST to `https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/databases/(default)/documents{$path}` with `Authorization: Bearer <token>`; returns decoded JSON; throws on non-2xx.
  - `firebase_scrub_chat(string $uid): void` — `runQuery` for `world_chat` where `uid == $uid` (limit 300), then `commit` with one `update` per doc: fields `name: ''`, `admin: false`, `updateMask.fieldPaths: ['name','admin']`. Wrap in try/catch → `error_log('Scrub failed: ...')`, return.

- [ ] **Step 2: Hook the scrub into `account_remove`**

Immediately after `$pdo->commit();` (before the ad_rewards comment):

```php
// Best-effort: blanked names sa world chat; laging matagal na ang MySQL
// deletion kaya hindi ito makakagulo sa kanya.
if (firebase_enabled()) firebase_scrub_chat($uid);
```

- [ ] **Step 3: Update `api/README.md`**

Append a "World chat (Firebase)" section: (1) the two env vars `GHOSST_FIREBASE_SA_EMAIL` / `GHOSST_FIREBASE_SA_KEY` (base64 of the PEM: `powershell: [Convert]::ToBase64String([IO.File]::ReadAllBytes('key.pem'))`), blank = feature off; (2) the full Firestore rules block copied verbatim from the spec's "Firestore rules" section (owner pastes it in console); (3) note: if the project already has rules, merge the `world_chat` match block instead of replacing.

- [ ] **Step 4: Verify and commit**

Run: `php -l api/lib/firebase.php` and `php -l api/routes/account.php` → no syntax errors.
Grep check: `Select-String -Path api\README.md -Pattern 'GHOSST_FIREBASE_SA_KEY'` → at least one match.

```bash
git add api/lib/firebase.php api/routes/account.php api/README.md
git commit -m "feat(api): scrub chat names on account deletion + chat setup docs"
```

### Task 4: Flutter — deps, `ChatService`, `Backend.firebaseToken`

**Files:**
- Modify: `pubspec.yaml` (dependencies)
- Create: `lib/services/chat_service.dart`
- Modify: `lib/services/worker_backend.dart` (in the session group, after `signOut`, ~line 79)
- Test: `test/chat_service_test.dart`

**Interfaces:**
- Consumes: `Backend.currentUser()` / `Backend.isAdmin()` / new `Backend.firebaseToken()`.
- Produces (used by Task 5):
  - `class ChatMessage { final String uid, name, text; final bool admin; final int tsMillis; const ChatMessage({required ...}); }`
  - `abstract class ChatClient { bool get ready; Stream<List<ChatMessage>> messages(); Future<String?> send(String text); Future<void> signOut(); }`
  - `class ChatService implements ChatClient` — static `ready` (false until `init()` succeeds), `static Future<void> init()` (no-arg `Firebase.initializeApp()`, catch → stays false), `static Future<bool> get started` (completes once `init()` settles with its verdict; in widget tests `main()` never ran so it never completes — the fallback must render, not hang), `static Future<bool> ensureSignedIn()` (token → `signInWithCustomToken`; re-mint when the cached user's `admin` claim mismatches `Backend.isAdmin()`; false on any failure), `send()` honoring validate + cooldown.
  - Pure, testable statics: `static String? validate(String text)` (null = valid: trimmed non-empty, ≤500), `static String fallbackName(String displayName, String uid)`, `static bool cooldownPassed(DateTime? lastSend, DateTime now)`, `static const Duration cooldown = Duration(seconds: 5)`.

- [ ] **Step 1: Add dependencies**

Run: `flutter pub add firebase_core firebase_auth cloud_firestore` (resolves latest compatible versions).

- [ ] **Step 2: Write the failing tests (`test/chat_service_test.dart`, plain `flutter_test`, no Firebase calls)**

Tests: `validate('')` and `validate('   ')` → non-null; `validate('x' * 501)` → non-null; `validate('x' * 500)` and `validate(' ok ')` → null. `fallbackName('Jeric', uid)` → `'Jeric'`; `fallbackName('', 'abcdef01-…')` → `'Anon-abcdef'`; `fallbackName('   ', uid)` → `Anon-…`. `cooldownPassed(null, now)` → true; `cooldownPassed(now, now.add(2s))` → false; `cooldownPassed(now, now.add(6s))` → true.

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/chat_service_test.dart`
Expected: FAIL — `chat_service.dart` does not exist.

- [ ] **Step 4: Implement `lib/services/chat_service.dart`**

House style of `adblock_detector.dart` (static service, injectable seams, fail-open comments). Notes the signature/tests leave open: `send()` writes `{uid, name, text, admin, ts: FieldValue.serverTimestamp()}` with `name = fallbackName(displayName, uid)`; the `messages()` stream maps docs skipping ones with a null `ts` (pending server timestamp on first snapshot); `signOut()` signs out of `FirebaseAuth` guarded by try/catch. Add `Backend.firebaseToken()` to `worker_backend.dart`:

```dart
/// Custom token para sa world chat (503 chat_disabled kapag hindi naka-setup).
static Future<String> firebaseToken() async =>
    (await _api.get('/firebase/token'))['token'] as String;
```

- [ ] **Step 5: Run tests to verify they pass; analyze; commit**

Run: `flutter test test/chat_service_test.dart` → all PASS. `flutter analyze` → No issues found!

```bash
git add pubspec.yaml pubspec.lock lib/services/chat_service.dart lib/services/worker_backend.dart test/chat_service_test.dart
git commit -m "feat: ChatService — Firebase custom-token sign-in, validation, cooldown"
```

### Task 5: Flutter — `ChatScreen`, shell tab, sign-out wiring

**Files:**
- Create: `lib/screens/chat_screen.dart`
- Modify: `lib/main.dart` (imports; `main()` after `unawaited(Push.init());` line 39; `pages` list line 573-588; `destinations` line 590-601; `_signOut` and the `onSignedOut` wiring)
- Test: `test/chat_screen_test.dart`

**Interfaces:**
- Consumes: `ChatClient`, `ChatMessage`, `ChatService` from Task 4; `GlowCard`, `Pressable` from `premium.dart`; `AppColors`/`AppText`/`AppSpace` from `theme.dart`; screen shape of `AnnouncementsScreen` (constructor-injected seam, `embedded` flag).
- Produces: `class ChatScreen extends StatefulWidget` — `const ChatScreen({super.key, this.embedded = true, ChatClient? client})`; injectable `client` defaults to `ChatService`.

- [ ] **Step 1: Write the failing widget tests (`test/chat_screen_test.dart`)**

A `_FakeClient implements ChatClient` (stream controller). Tests: (1) `client` with `ready=false` → `pumpWidget` shows the text `Chat unavailable`; (2) fake streaming two `ChatMessage`s — one `admin: true`, one `name: ''` → pump finds both message texts, an `ADMIN` chip, and `Deleted user`; (3) empty input field + send tap → fake's `send` never called, non-empty → called with the typed text.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/chat_screen_test.dart`
Expected: FAIL — `chat_screen.dart` does not exist.

- [ ] **Step 3: Implement `lib/screens/chat_screen.dart`**

Style of `announcements_screen.dart`. Behavior pinned by the spec: `ready == false` renders the fallback immediately (no pending spinner — a never-completed `init()` in widget tests must render the fallback, not hang); when `ChatService.init()` later completes the screen rebuilds into the signed-in state (`ChatService.started` future or listener — the implementer picks the simplest mechanism that satisfies both tests and the flash-free transition). Reversed message list (newest at bottom), `GlowCard` rows: name (+ `ADMIN` chip when `admin`), time, text; input bar with `Pressable` send; errors from `send()` surface as a brief `SnackBar`, invalid text is a no-op.

- [ ] **Step 4: Wire the shell in `lib/main.dart`**

`unawaited(ChatService.init());` right after `unawaited(Push.init());`. In `pages`: `const ChatScreen(embedded: true),` after `const AnnouncementsScreen(embedded: true),` (chat gets index 4; existing indices 0–3 and the `active: tab == 2` checks are untouched). In `destinations`: `_NavItem(Icons.chat_bubble_outline_outlined, Icons.chat_bubble, 'Chat'),` after News. Add `unawaited(ChatService.signOut());` inside both the `Backend.onSignedOut = () {` callback (line 282) and `_signOut()` (line 301) so the Firebase session dies with the backend session.

- [ ] **Step 5: Run the full suite to verify nothing broke; analyze; commit**

Run: `flutter test` → all pass (existing 78 + new). `flutter analyze` → No issues found!

```bash
git add lib/screens/chat_screen.dart lib/main.dart test/chat_screen_test.dart
git commit -m "feat: world chat tab with claim-verified senders"
```

### Task 6: Docs — privacy policy + deletion page

**Files:**
- Modify: `docs/index.html`
- Modify: `docs/delete-account.html`

**Interfaces:**
- Consumes: the exact draft wording in the spec's "Privacy & compliance edits" section.
- Produces: truthful public pages; no code.

- [ ] **Step 1: Locate and replace the Firebase sentence in `docs/index.html`**

Run: `Select-String -Path docs\index.html -Pattern 'no email'` to find the sentence. Replace it with the spec's draft: "Firebase receives your account ID and display name (or an anonymous handle) to deliver world chat messages; message text is stored there. No email, coin balance, or purchase data is sent to Firebase."

- [ ] **Step 2: Add the chat line to `docs/delete-account.html`**

Find the "What is deleted" list (grep `deleted`), add one item with the spec's draft: "World chat messages are kept but your name on them is blanked (best-effort at deletion)."

- [ ] **Step 3: Verify and commit**

Run: `Select-String -Path docs\index.html -Pattern 'world chat'` → 1+ match; `Select-String -Path docs\index.html -Pattern 'no email, account ID'` → 0 matches; same idea for the delete page.

```bash
git add docs/index.html docs/delete-account.html
git commit -m "docs: privacy + deletion pages cover world chat data"
```

Owner follow-up (not a repo step): submit the Play Data Safety update declaring account ID + user content shared with Firebase.

### Task 7: Full gates + release-safety build

**Files:** none created (verification only).

- [ ] **Step 1: Run all gates**

Run: `flutter analyze` → No issues found! `flutter test` → all pass. `php -l` on all four touched PHP files → no syntax errors.

- [ ] **Step 2: Release-safety build (catches R8/gradle issues the tests cannot)**

Run: `flutter build apk --release --flavor play --dart-define=USE_TEST_ADS=true`
Expected: `✓ Built build/app/outputs/flutter-apk/app-play-release.apk`.

- [ ] **Step 3: Hand off to the owner**

Report done. Owner checklist before merge to `main` (from the spec): create Firestore database + paste rules, generate the service-account key, set the two Hostinger env vars, upload `api/`, verify one message round-trip. No `git push` from the agent.
