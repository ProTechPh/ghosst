# Push Notifications + In-App Announcements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Notify users while the app is closed when a product is listed, a sold-out duration pool is restocked, or the owner posts an announcement, and show manual announcements as a dismissible banner inside the app.

**Architecture:** The Flutter app initialises the OneSignal SDK (no token table, no user ids sent), broadcasts are sent by the PHP API through the OneSignal REST API from `api/lib/push.php`, and manual announcements live in a new `app_announcements` table that also feeds the in-app banner. Auto pushes hang off `products_create` and `keys_add`; every send is fire-and-forget so it can never fail the admin request.

**Tech Stack:** Flutter 3.47 / Dart 3.11, `onesignal_flutter`, PHP 8 on Hostinger + MySQL, existing Dio `ApiClient` + `Backend` surface.

**Spec:** `docs/superpowers/specs/2026-11-03-push-announcements-design.md`

## Global Constraints

- Android only; two flavors (`play`, `direct`), `direct` installs as `com.astrixtech.ghosst.direct`. Both must be Firebase Android apps once credentials arrive.
- Gate for every task: `C:\flutter\bin\flutter.bat analyze` (clean) and `C:\flutter\bin\flutter.bat test` (all green). Tests never touch the network.
- PHP: `declare(strict_types=1)` in every file, `ApiError`/`read_json()`/`one()`/`scalar()`/`run_sql()`/`uuid4()`/`now_utc()` from `api/lib/`, JSON envelope unchanged.
- Secrets in `api/config.php` via `getenv()`, blank means the feature is off. Push additionally requires `HTTP_HOST === PUSH_HOST` (`ghossthub.com`, `GHOSST_PUSH_HOST` override).
- Announcement: `title` ≤ 120 chars after trim, `body` required after trim, `expires_at = now + 7 days` (UTC).
- All app tables use the `app_` prefix; DDL is `CREATE TABLE IF NOT EXISTS`.
- Client code goes through `Backend` (`lib/services/worker_backend.dart`) → `ApiBackend` (`lib/services/api_backend.dart`); screens never call `_api` directly.
- Push failures are logged only: `error_log('push ...')`, never thrown, never surfaced as an error toast.

## Review Focus

- OneSignal slow/down while an admin adds keys → `POST /v1/admin/keys` and `POST /v1/admin/announcements` still return 200 within a few seconds.
- Local `php -S 127.0.0.1:8099` with a real REST key pasted in → still no broadcast (host guard).
- Keys pasted into a pool that already has stock, with `duration` empty or `NULL` → no push; only a 0 → >0 pool change pushes once.
- `expires_at` in the past (and `active = 0`) → `GET /v1/announcements` returns `null`, no banner.
- Banner fetch failing (offline / 500) → home shell still renders the coin header and tabs, no error toast.
- Notification permission prompt must not appear on the splash/tamper/ad-block gates.

---

### Task 1: Announcement model, unread rule, device-side dismiss store

**Files:**
- Modify: `lib/services/models.dart` (append after the last class)
- Create: `lib/services/announcement_store.dart`
- Test: `test/announcement_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class Announcement { final String id, title, body, createdAt; const Announcement({required String id, required String title, required String body, String createdAt = ''}); factory Announcement.fromJson(Map<String, dynamic> json); }`
  `Announcement? unreadAnnouncement(Announcement? a, String dismissedId)` (top-level, in `models.dart`)
  `class AnnouncementStore { static Future<String> dismissedId(); static Future<void> dismiss(String id); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/announcement_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/models.dart';

void main() {
  Announcement sample() => const Announcement(
    id: 'a1',
    title: 'Bagong stock',
    body: 'Netflix — 1 Month',
  );

  test('parses the API payload', () {
    final a = Announcement.fromJson({
      'id': 'a1',
      'title': 'Bagong stock',
      'body': 'Netflix — 1 Month',
      'createdAt': '2026-11-03 10:00:00',
    });
    expect(a.id, 'a1');
    expect(a.body, 'Netflix — 1 Month');
    expect(a.createdAt, '2026-11-03 10:00:00');
  });

  test('missing fields do not throw', () {
    final a = Announcement.fromJson({'id': 'x'});
    expect(a.title, '');
    expect(a.createdAt, '');
  });

  test('unread only when the id differs from the dismissed one', () {
    expect(unreadAnnouncement(sample(), ''), isNotNull);
    expect(unreadAnnouncement(sample(), 'other'), isNotNull);
    expect(unreadAnnouncement(sample(), 'a1'), isNull);
    expect(unreadAnnouncement(null, ''), isNull);
  });
}
```

- [ ] **Step 2: Run it and see it fail**

Run: `C:\flutter\bin\flutter.bat test test/announcement_test.dart`
Expected: FAIL — `Announcement` / `unreadAnnouncement` not defined.

- [ ] **Step 3: Implement**

`Announcement` in `lib/services/models.dart`, mapping like `ApiProduct.fromJson` (`json['title'] as String? ?? ''`), plus:

```dart
Announcement? unreadAnnouncement(Announcement? a, String dismissedId) =>
    (a == null || a.id == dismissedId) ? null : a;
```

`lib/services/announcement_store.dart` mirrors `SessionStore`'s `FlutterSecureStorage` usage, key `ghosst.announcement.dismissed`, `read` defaults to `''`.

- [ ] **Step 4: Run it and see it pass**

Run: `C:\flutter\bin\flutter.bat test test/announcement_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/models.dart lib/services/announcement_store.dart test/announcement_test.dart
git commit -m "feat: announcement model and dismiss store"
```

---

### Task 2: Banner widget

**Files:**
- Create: `lib/announcement_banner.dart`
- Test: `test/announcement_banner_test.dart`

**Interfaces:**
- Consumes: `Announcement` from Task 1.
- Produces: `class AnnouncementBanner extends StatelessWidget { const AnnouncementBanner({super.key, required this.announcement, required this.onDismiss}); final Announcement announcement; final VoidCallback onDismiss; }`

- [ ] **Step 1: Write the failing test**

```dart
// test/announcement_banner_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/announcement_banner.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

void main() {
  testWidgets('shows the announcement and dismisses', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var dismissed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: AnnouncementBanner(
          announcement: const Announcement(id: 'a1', title: 'Bagong stock', body: 'Netflix — 1 Month'),
          onDismiss: () => dismissed++,
        ),
      ),
    ));

    expect(find.text('Bagong stock'), findsOneWidget);
    expect(find.text('Netflix — 1 Month'), findsOneWidget);
    expect(tester.takeException(), isNull); // no overflow on a 320px phone

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(dismissed, 1);
  });
}
```

- [ ] **Step 2: Run it and see it fail**

Run: `C:\flutter\bin\flutter.bat test test/announcement_banner_test.dart`
Expected: FAIL — `lib/announcement_banner.dart` not found.

- [ ] **Step 3: Implement `AnnouncementBanner`**

Same visual grammar as `premium.dart` cards: rounded (`AppRadius.input`), `AppColors.primary` border at alpha 0.30, dark fill, title in `AppText.subtitle`, body in `AppText.caption` with `AppColors.textDim`, trailing `IconButton` with `tooltip: 'Dismiss'` and `Icons.close`, `onPressed: onDismiss`. Wrap the text column in `Expanded` and let the body shrink, so a long announcement cannot overflow.

- [ ] **Step 4: Run it and see it pass**

Run: `C:\flutter\bin\flutter.bat test test/announcement_banner_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/announcement_banner.dart test/announcement_banner_test.dart
git commit -m "feat: announcement banner widget"
```

---

### Task 3: API — announcements table, push helper, endpoints

**Files:**
- Modify: `api/config.php` (after the Cloudinary block, near other table constants)
- Create: `api/lib/push.php`
- Create: `api/routes/announcements.php`
- Modify: `api/index.php` (ROUTES array, after the claims entries)
- Create: `C:\laragon\www\database\app_announcements.sql`

**Interfaces:**
- Consumes: `require_admin()`, `read_json()`, `one()`, `run_sql()`, `uuid4()`, `now_utc()`.
- Produces: `push_send(string $title, string $body): bool`, `push_enabled(): bool`, `announcements_latest(array $ctx): array` → `['announcement' => null|array]`, `announcements_create(array $ctx): array` → `['ok' => true, 'announcement' => array, 'pushed' => bool]`, `announcement_json(array $row): array` → `['id','title','body','createdAt']`.
- Tables: `T_ANNOUNCEMENTS` = `app_announcements`.

- [ ] **Step 1: Add the DDL and config**

`C:\laragon\www\database\app_announcements.sql`:

```sql
CREATE TABLE IF NOT EXISTS `app_announcements` (
  `id` char(36) NOT NULL,
  `title` varchar(120) NOT NULL,
  `body` text NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `expires_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_active_created` (`active`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

Run it once on Hostinger (`phpMyAdmin` → SQL), and note it in SETUP.md later (Task 7).

`api/config.php`: add next to the other `T_*` constants

```php
define('T_ANNOUNCEMENTS', 'app_announcements');

/** OneSignal push. Blank REST key = feature off. */
define('ONESIGNAL_APP_ID', getenv('GHOSST_ONESIGNAL_APP_ID') ?: '');
define('ONESIGNAL_REST_KEY', getenv('GHOSST_ONESIGNAL_REST_KEY') ?: '');
/** Only this host may broadcast (GHOSST_PUSH_HOST override). */
define('PUSH_HOST', getenv('GHOSST_PUSH_HOST') ?: 'ghossthub.com');
```

- [ ] **Step 2: Implement `api/lib/push.php`**

```php
function push_enabled(): bool;   // REST key + app id non-empty AND HTTP_HOST === PUSH_HOST
function push_send(string $title, string $body): bool;
```

`push_send`: if `!push_enabled()` → `error_log('push skipped: host/key')`, return `false`. Otherwise `curl_init('https://api.onesignal.com/notifications')`, JSON body `{app_id, included_segments: ['Subscribed Users'], headings: {en: title}, contents: {en: body}}`, headers `Authorization: Key <REST_KEY>`, `Content-Type: application/json`, `CURLOPT_TIMEOUT => 5`, `CURLOPT_RETURNTRANSFER => true`. Any non-2xx or curl failure → `error_log('push failed: ' . ...)`, return `false`; success returns `true`. No exceptions escape.

- [ ] **Step 3: Implement `api/routes/announcements.php`**

- `announcements_create`: `require_admin($ctx)`; `read_json()`; trim title (`mb_substr(..., 0, 120, 'UTF-8')`), trim body; empty either → `throw new ApiError(400, 'invalid_announcement', 'Title and body are required')`; insert `id` (`uuid4()`), `active` 1, `expires_at = gmdate('Y-m-d H:i:s', time() + 7 * 86400)`, `created_at = now_utc()`; re-read the row with `one()`; `$pushed = push_send($title, $body);` (after the insert, never before); return `['ok' => true, 'announcement' => announcement_json($row), 'pushed' => $pushed]`.
- `announcements_latest`: `one('SELECT id, title, body, created_at FROM ' . T_ANNOUNCEMENTS . ' WHERE active = 1 AND (expires_at IS NULL OR expires_at > UTC_TIMESTAMP()) ORDER BY created_at DESC LIMIT 1')`; return `['announcement' => $row ? announcement_json($row) : null]`.

- [ ] **Step 4: Register the routes**

In `api/index.php` `ROUTES`, right after the claims pair:

```php
['GET',    '#^/v1/announcements$#',                    'announcements_latest',    'required'],
['POST',   '#^/v1/admin/announcements$#',              'announcements_create',    'required'],
```

- [ ] **Step 5: Verify by hand against the local server**

```powershell
php -S 127.0.0.1:8099 -t C:\laragon\www\api C:\laragon\www\api\index.php
```

Register/login an admin, then:
- `POST /v1/admin/announcements` with `{"title":"Test","body":"Hello"}` → 200, `pushed: false` in the response, and the PHP log shows `push skipped: host/key` (expected on 127.0.0.1 — this is the Review Focus guard).
- `GET /v1/announcements` with the same token → the row back.
- SQL `UPDATE app_announcements SET expires_at = '2020-01-01 00:00:00'` → `GET` returns `{"announcement":null}`.

Also `php -l` every touched PHP file.

- [ ] **Step 6: Commit**

```bash
git add api/config.php api/lib/push.php api/routes/announcements.php api/index.php
git commit -m "feat(api): announcement endpoint and OneSignal push helper"
```

---

### Task 4: Auto pushes on new product and restock

**Files:**
- Modify: `api/routes/products.php` (`products_create`)
- Modify: `api/routes/keys.php` (`keys_add`)

**Interfaces:**
- Consumes: `push_send(string $title, string $body): bool` from Task 3.
- Produces: nothing new for other tasks.

- [ ] **Step 1: `products_create`**

Hoist the active flag (`$active = ($body['active'] ?? true) === false ? 0 : 1;`) and use it in the insert as today. After the insert succeeds:

```php
if ($active === 1) push_send('Bagong product: ' . $name, 'Bagong listing sa store.');
```

- [ ] **Step 2: `keys_add` — count the pool before inserting**

Immediately after the product lookup (change that query to `SELECT id, name`), before the `array_chunk` loop:

```php
$before = (int) scalar(
    'SELECT COUNT(*) FROM ' . T_KEYS
    . " WHERE product_id = ? AND status = 'available' AND COALESCE(duration, '') = ?",
    [$productId, $duration]
);
```

After the loop, before the return:

```php
if ($before === 0 && $added > 0) {
    push_send(
        'Bagong stock: ' . (string) $product['name'],
        $duration !== '' ? $duration : 'Available na ulit'
    );
}
```

`COALESCE` matters: keys inserted by older code may carry `NULL` duration, and a bare `duration = ''` would read every pasted pool as empty and push on every paste (Review Focus).

- [ ] **Step 3: Verify by hand**

Local server with a real admin token and the OneSignal key left blank:
- Create a product → response 200, log line `push skipped`.
- Sell out a pool (`UPDATE app_keys SET status='claimed' WHERE product_id=? AND duration=?`), post keys for it → one `push skipped` line.
- Post more keys into that now-stocked pool → **no** new push line.
- `php -l` both files.

- [ ] **Step 4: Commit**

```bash
git add api/routes/products.php api/routes/keys.php
git commit -m "feat(api): push on new product and on restock"
```

---

### Task 5: App wiring — Backend methods, home banner, admin compose

**Files:**
- Modify: `lib/services/api_backend.dart` (after `downloadTicket`)
- Modify: `lib/services/worker_backend.dart`
- Modify: `lib/main.dart` (`_HomeShellState`)
- Modify: `lib/screens/admin_screen.dart`

**Interfaces:**
- Consumes: `Announcement`, `unreadAnnouncement`, `AnnouncementStore` (Task 1), `AnnouncementBanner` (Task 2), `GET/POST /v1/announcements`.
- Produces: `ApiBackend.announcement() → Future<Announcement?>`, `ApiBackend.sendAnnouncement({required String title, required String body}) → Future<bool>`, `Backend.announcement()`, `Backend.sendAnnouncement(...)`.

- [ ] **Step 1: `ApiBackend`**

```dart
Future<Announcement?> announcement() async {
  final res = await _api.get('/announcements');
  final raw = res['announcement'];
  return raw is Map<String, dynamic> ? Announcement.fromJson(raw) : null;
}

Future<bool> sendAnnouncement({required String title, required String body}) async {
  final res = await _api.post('/admin/announcements', data: {'title': title, 'body': body});
  return res['pushed'] as bool? ?? false;
}
```

- [ ] **Step 2: `Backend` statics** — same signatures, delegating to `_apiBackend`, matching the style of `coins()`:

```dart
static Future<Announcement?> announcement() async {
  if (await _session.accessToken() == null) return null;
  try {
    return await _apiBackend.announcement();
  } on ApiException {
    return null; // a blip must not show a banner-shaped error
  }
}

static Future<bool> sendAnnouncement({required String title, required String body}) =>
    _apiBackend.sendAnnouncement(title: title, body: body);
```

- [ ] **Step 3: Banner in `_HomeShellState`**

Add `Announcement? announcement;` and `String dismissedId = '';`. Imports in `main.dart`: `announcement_banner.dart`, `services/announcement_store.dart` (`Announcement` and `unreadAnnouncement` already arrive through the existing `services/worker_backend.dart` export). In `_refresh()`, before `setState`, fetch both inside one `try` so a failure means "no banner":

```dart
Announcement? fresh;
try {
  final stored = await AnnouncementStore.dismissedId();
  final latest = await Backend.announcement();
  dismissedId = stored;
  fresh = unreadAnnouncement(latest, stored);
} catch (_) {
  fresh = null;
}
```

Assign `announcement = fresh` inside the existing `setState`. Dismiss:

```dart
Future<void> _dismissAnnouncement() async {
  final id = announcement?.id ?? '';
  setState(() => announcement = null);
  if (id.isNotEmpty) await AnnouncementStore.dismiss(id);
}
```

Body: wrap the stack instead of replacing it —

```dart
body: Column(
  children: [
    if (announcement != null)
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, 0),
        child: AnnouncementBanner(announcement: announcement!, onDismiss: _dismissAnnouncement),
      ),
    Expanded(child: IndexedStack(index: safeIndex, children: pages)),
  ],
),
```

- [ ] **Step 4: Admin send card**

In `_AdminScreenState`: `final announcementTitle = TextEditingController();`, `final announcementBody = TextEditingController();` (dispose both), and

```dart
Future<void> _sendAnnouncement() async {
  final title = announcementTitle.text.trim();
  final body = announcementBody.text.trim();
  if (title.isEmpty || body.isEmpty) {
    setState(() => message = 'Title and body are required.');
    return;
  }
  setState(() => busy = true);
  try {
    final pushed = await Backend.sendAnnouncement(title: title, body: body);
    setState(() {
      message = pushed
          ? 'Announcement posted and pushed.'
          : 'Announcement posted. Push is not configured on this server.';
      announcementTitle.clear();
      announcementBody.clear();
    });
  } catch (e) {
    setState(() => message = 'Announcement failed: $e');
  } finally {
    if (mounted) setState(() => busy = false);
  }
}
```

Render one `GlowCard` directly after the failure/message block in `build`, before `SectionLabel('Products ...')`: `SectionLabel('Announcement')`, `TextField` (label `TITLE`), `TextField` (label `BODY`, `maxLines: 3`), and a `FilledButton` labelled `Send announcement`, `onPressed: busy ? null : _sendAnnouncement`. Everything else in the panel stays untouched.

- [ ] **Step 5: Verify**

Run: `C:\flutter\bin\flutter.bat analyze` → no issues.
Run: `C:\flutter\bin\flutter.bat test` → all pass.
Manual, against the local API:
- Sign in as admin, post an announcement → banner shows on the home tab.
- Close it, restart the app → it stays closed; a second announcement shows again.
- Stop the local API (or airplane mode) and cold-start signed in → no banner, no error toast, coin header and tabs render (Review Focus).

- [ ] **Step 6: Commit**

```bash
git add lib/services/api_backend.dart lib/services/worker_backend.dart lib/main.dart lib/screens/admin_screen.dart
git commit -m "feat: in-app announcement banner and admin compose"
```

---

### Task 6: OneSignal SDK wiring

**Files:**
- Modify: `pubspec.yaml` (dependency added by `flutter pub add onesignal_flutter`)
- Create: `lib/services/push.dart`
- Modify: `lib/main.dart` (`main()` and `_HomeState`)
- Test: `test/push_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class Push { static bool get configured; static Future<void> init(); static Future<void> requestPermission(); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/push_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/services/push.dart';

void main() {
  test('unconfigured build is inert and never throws', () async {
    // No --dart-define in tests, so there is no app id and no platform channel.
    expect(Push.configured, isFalse);
    await Push.init();
    await Push.requestPermission();
  });
}
```

- [ ] **Step 2: Run it and see it fail**

Run: `C:\flutter\bin\flutter.bat test test/push_test.dart`
Expected: FAIL — `lib/services/push.dart` not found.

- [ ] **Step 3: Implement and add the dependency**

`C:\flutter\bin\flutter.bat pub add onesignal_flutter`

```dart
// lib/services/push.dart
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// OneSignal broadcast notifications. An empty app id (the default) makes the
/// whole file inert, so builds without credentials behave exactly as before.
class Push {
  Push._();

  static const appId = String.fromEnvironment('ONESIGNAL_APP_ID');

  static bool get configured => appId.isNotEmpty;

  static Future<void> init() async {
    if (!configured) return;
    try {
      OneSignal.initialize(appId);
    } catch (_) {
      // A push SDK that cannot start must never block the app.
    }
  }

  static Future<void> requestPermission() async {
    if (!configured) return;
    try {
      OneSignal.Notifications.requestPermission(true);
    } catch (_) {}
  }
}
```

- [ ] **Step 4: Call it from the app shell**

`main.dart`: `unawaited(Push.init());` at the top of `main()` (before `runApp`), and in `_HomeState` where the signed-in branch is chosen, call `Push.requestPermission()` once — never from `_AppEntry`'s splash/tamper/ad-block gates (Review Focus).

Add `import 'services/push.dart';` where needed.

- [ ] **Step 5: Verify**

Run: `C:\flutter\bin\flutter.bat test test/push_test.dart` → PASS.
Run: `C:\flutter\bin\flutter.bat analyze` → no issues.
Run: `C:\flutter\bin\flutter.bat build apk --debug --flavor play` → succeeds without any Firebase file (nothing references it yet).
Manual: cold start on a configured build → no permission dialog on the splash/tamper/ad-block screens; the system prompt appears only after the home shell opens.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/services/push.dart lib/main.dart test/push_test.dart
git commit -m "feat: OneSignal SDK wiring behind an empty app id"
```

- [ ] **Step 7 (blocked on the owner): activate real push**

Only once the owner provides the OneSignal app id and `google-services.json` with **both** packages `com.astrixtech.ghosst` and `com.astrixtech.ghosst.direct`:

1. Drop the file at `android/app/google-services.json`.
2. `android/settings.gradle.kts`: add `id("com.google.gms.google-services") version "4.4.3" apply false` to the plugins block.
3. `android/app/build.gradle.kts`: add `id("com.google.gms.google-services")` after the Flutter plugin.
4. Build with `--dart-define=ONESIGNAL_APP_ID=<id>` for both flavors; confirm an installed device appears under OneSignal → Audience → Subscriptions.
5. Set `ONESIGNAL_APP_ID` / `ONESIGNAL_REST_KEY` in `api/config.php` on Hostinger.

---

### Task 7: Owner-facing docs

**Files:**
- Modify: `docs/index.html` (sections 2 and 3)
- Modify: `SETUP.md` (data model, config, release checklist, troubleshooting)

**Interfaces:**
- Consumes: everything above, especially the exact config constant names and DDL path.
- Produces: nothing code-facing.

- [ ] **Step 1: Privacy policy**

Section 2 (Third-Party Services): one paragraph — the app uses Firebase Cloud Messaging via OneSignal to deliver device notifications; only an anonymous push subscription id is involved and no account data is shared. Section 3 (Permissions): add `POST_NOTIFICATIONS` — notifications are optional and can be denied without losing any app feature.

- [ ] **Step 2: SETUP.md**

- Data model table: row for `app_announcements` pointing at `C:\laragon\www\database\app_announcements.sql`.
- Config section: `GHOSST_ONESIGNAL_APP_ID`, `GHOSST_ONESIGNAL_REST_KEY`, `GHOSST_PUSH_HOST` (default `ghossthub.com`), blank key = push off.
- Release checklist: `google-services.json` present and covering both package names; OneSignal app id passed via `--dart-define`.
- Troubleshooting row: "No notification arrives" → check `google-services.json` package match, OneSignal subscription count, and that `ONESIGNAL_REST_KEY` is set on the **host**, since local/pushes from a dev host are skipped by design.

- [ ] **Step 3: Verify and commit**

Run: `C:\flutter\bin\flutter.bat analyze` (docs are HTML/MD but the gate ran green at the end of the branch).
Open `docs/index.html` in a browser once to confirm nothing broke visually.

```bash
git add docs/index.html SETUP.md
git commit -m "docs: push notifications, config and privacy notes"
```
