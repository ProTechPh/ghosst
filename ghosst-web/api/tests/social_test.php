<?php
declare(strict_types=1);

if (!function_exists('mb_strlen')) {
    function mb_strlen(string $string, ?string $encoding = null): int { return strlen($string); }
}
if (!function_exists('mb_substr')) {
    function mb_substr(string $string, int $start, ?int $length = null, ?string $encoding = null): string {
        return $length === null ? substr($string, $start) : substr($string, $start, $length);
    }
}

require __DIR__ . '/../lib/social.php';
require __DIR__ . '/../routes/users.php';
require __DIR__ . '/../routes/feedback.php';
require __DIR__ . '/../routes/follows.php';
require __DIR__ . '/../lib/idempotency.php';
require __DIR__ . '/../lib/reels.php';
require __DIR__ . '/../routes/reels.php';
require __DIR__ . '/../routes/reel_social.php';
require __DIR__ . '/../routes/admin_reels.php';

if (!defined('REEL_UPLOAD_SECRET')) define('REEL_UPLOAD_SECRET', 'test-reel-secret');
if (!defined('REEL_PUBLIC_BASE_URL')) define('REEL_PUBLIC_BASE_URL', 'https://video.example/media');
if (!defined('REEL_UPLOAD_URL')) define('REEL_UPLOAD_URL', 'https://video.example/upload.php');

if (!defined('T_USERS')) define('T_USERS', 'users');
if (!defined('T_IDEM')) define('T_IDEM', 'app_idempotency');
$GLOBALS['social_user_row'] = null;
$GLOBALS['social_viewer_row'] = null;
$GLOBALS['social_edge'] = null;
$GLOBALS['social_reel_rows'] = [];
$GLOBALS['social_queries'] = [];
$GLOBALS['social_fake_db'] = new class {
    public bool $inTransaction = false;
    public array $idemRows = [];
    public function beginTransaction(): void { $this->inTransaction = true; }
    public function commit(): void { $this->inTransaction = false; }
    public function rollBack(): void { $this->inTransaction = false; }
    public function prepare(string $sql): object {
        $db = $this;
        return new class($db, $sql) {
            public bool $inserted = false;
            private array|false|null $row = null;
            public function __construct(private object $db, private string $sql) {}
            public function execute(array $params): bool {
                if (str_contains($this->sql, 'INSERT IGNORE INTO app_idempotency')) {
                    $key = $params[0] . ':' . $params[1];
                    $this->inserted = !isset($this->db->idemRows[$key]);
                    if ($this->inserted) $this->db->idemRows[$key] = ['response' => $params[2], 'hash' => $params[3]];
                    return true;
                }
                if (str_contains($this->sql, 'SELECT response, request_hash FROM app_idempotency')) {
                    $row = $this->db->idemRows[$params[0] . ':' . $params[1]] ?? null;
                    $this->row = $row === null ? false : ['response' => $row['response'], 'request_hash' => $row['hash']];
                    return true;
                }
                if (str_contains($this->sql, 'UPDATE app_idempotency SET response')) {
                    $this->db->idemRows[$params[1] . ':' . $params[0]]['response'] = $params[2];
                    return true;
                }
                return true;
            }
            public function rowCount(): int { return $this->inserted ? 1 : 0; }
            public function fetch(): array|false { return $this->row ?? false; }
        };
    }
};

function db(): object
{
    return $GLOBALS['social_fake_db'];
}

function social_query(string $sql, array $params): void
{
    $GLOBALS['social_queries'][] = ['sql' => $sql, 'params' => $params];
}

function one(string $sql, array $params = []): ?array
{
    social_query($sql, $params);
    if (str_contains($sql, 'SELECT response, request_hash FROM app_idempotency')) {
        $row = $GLOBALS['social_fake_db']->idemRows[$params[0] . ':' . $params[1]] ?? null;
        return $row === null ? null : ['response' => $row['response'], 'request_hash' => $row['hash']];
    }
    if (str_contains($sql, 'FROM app_reel_comments c JOIN app_reels')) {
        return ['text' => 'Reported comment', 'caption' => 'Reported caption', 'id' => 'comment-1'];
    }
    if (str_contains($sql, 'SELECT caption FROM app_reels')) {
        return ['caption' => 'Reported caption'];
    }
    if (str_contains($sql, 'SELECT id FROM app_reels')) {
        return ['id' => 'reel-1'];
    }
    if (str_contains($sql, 'SELECT id, user_id, sha256, size_bytes FROM app_reels')) {
        return ['id' => 'r1', 'user_id' => '42', 'sha256' => str_repeat('a', 64), 'size_bytes' => 123, 'status' => 'pending'];
    }
    if (str_contains($sql, 'FROM app_reels') && str_contains($sql, 'FOR UPDATE')) {
        return ['id' => 'r1', 'user_id' => '42', 'sha256' => str_repeat('a', 64), 'size_bytes' => 123, 'status' => $GLOBALS['social_reel_status'] ?? 'visible', 'poster_url' => null];
    }
    if (!str_contains($sql, 'FROM users')) return null;
    if (($params[0] ?? null) == 42 && $GLOBALS['social_viewer_row'] !== null) {
        return $GLOBALS['social_viewer_row'];
    }
    return $GLOBALS['social_user_row'];
}

function all_rows(string $sql, array $params = []): array
{
    social_query($sql, $params);
    if (str_contains($sql, 'FROM app_reel_media')) return $GLOBALS['social_reel_media_rows'] ?? [];
    if (str_contains($sql, 'FROM app_reel_comments')) return $GLOBALS['social_comment_rows'] ?? [];
    return str_contains($sql, 'FROM app_reels') ? $GLOBALS['social_reel_rows'] : [];
}

function scalar(string $sql, array $params = [])
{
    social_query($sql, $params);
    if (str_contains($sql, 'SELECT 1 FROM app_follows')) return $GLOBALS['social_edge'];
    if (str_contains($sql, 'WHERE f.creator_id')) return 12;
    if (str_contains($sql, 'WHERE f.follower_id')) return 7;
    if (str_contains($sql, 'FROM app_reels')) return 3;
    return null;
}

function run_sql(string $sql, array $params = []): int
{
    social_query($sql, $params);
    if (str_contains($sql, 'UPDATE app_idempotency SET response')) {
        $GLOBALS['social_fake_db']->idemRows[$params[1] . ':' . $params[0]]['response'] = $params[2];
    }
    if (str_contains($sql, 'INSERT IGNORE INTO app_follows')) $GLOBALS['social_edge'] = 1;
    if (str_contains($sql, 'DELETE FROM app_follows')) $GLOBALS['social_edge'] = null;
    return 1;
}

function check(bool $ok, string $label): void
{
    if (!$ok) {
        fwrite(STDERR, "FAIL: {$label}\n");
        exit(1);
    }
}

function api_error(callable $fn, int $status, string $label): void
{
    try {
        $fn();
    } catch (ApiError $e) {
        check($e->status === $status, $label . ' status');
        return;
    }
    check(false, $label . ' should throw');
}

class ApiError extends Exception {
    public string $errorMessage;
    public string $errorCode;
    public function __construct(public int $status, string $code, string $message, public int $retryAfter = 0) {
        $this->errorCode = $code;
        $this->errorMessage = $message;
    }
}

function read_json(): array
{
    return $GLOBALS['social_json_body'] ?? ['images' => [['position' => 1, 'imageUrl' => 'https://video.example/media/r1-1.jpg', 'sha256' => str_repeat('a', 64), 'sizeBytes' => 123]]];
}

function now_utc(): string { return gmdate('Y-m-d H:i:s'); }
function iso_time(?string $value): ?string { return $value; }
function header_value(string $name): string { return $GLOBALS['social_idem_key'] ?? ''; }
function uuid4(): string { return bin2hex(random_bytes(16)); }
function json_encode_body(array $value): string { return json_encode($value, JSON_THROW_ON_ERROR); }

$public = social_public_user([
    'id' => 42,
    'username' => 'jeric',
    'display_name' => 'Jeric',
    'avatar_url' => 'https://lh3.googleusercontent.com/a/example',
    'created_at' => '2026-01-01 00:00:00',
    'is_admin' => 1,
    'is_moderator' => 0,
    'email' => 'private@example.com',
    'password' => 'secret',
    'balance' => 999,
    'coins' => 123,
]);
check(array_keys($public) === ['id', 'displayName', 'username', 'avatarUrl', 'bio', 'coverUrl', 'isAdmin', 'isModerator'], 'public user allowlist');
check($public['id'] === '42' && $public['isAdmin'] === true && $public['isModerator'] === false, 'public user types');
check(!array_key_exists('email', $public) && !array_key_exists('password', $public) && !array_key_exists('balance', $public) && !array_key_exists('coins', $public), 'public user excludes private fields');

$GLOBALS['social_queries'] = [];
social_column_exists('users', 'avatar_url');
$schemaSql = $GLOBALS['social_queries'][0]['sql'] ?? '';
check(!str_contains($schemaSql, '?'), 'schema check avoids unsupported SHOW placeholder');
check(str_contains($schemaSql, "LIKE 'avatar_url'"), 'schema check quotes validated column name');

check(social_user_is_visible(['deleted_at' => null, 'is_banned' => 0]) === true, 'active user is visible');
check(social_user_is_visible(['deleted_at' => '2026-01-01', 'is_banned' => 0]) === false, 'deleted user is hidden');
check(social_user_is_visible(['deleted_at' => null, 'is_banned' => 1]) === false, 'banned user is hidden');

$GLOBALS['social_queries'] = [];
social_require_visible_reel('reel-1');
$visibleReelSql = $GLOBALS['social_queries'][0]['sql'] ?? '';
check(str_contains($visibleReelSql, 'FROM app_reels r'), 'visible reel lookup aliases reel table');

$profile = social_profile_user([
    'id' => 42,
    'username' => 'jeric',
    'display_name' => 'Jeric',
    'created_at' => '2026-01-01 00:00:00',
    'is_admin' => 0,
    'is_moderator' => 0,
], '42');
check($profile['isSelf'] === true && $profile['isFollowing'] === false, 'profile viewer flags');
check($profile['followerCount'] === 0 && $profile['followingCount'] === 0 && $profile['reelCount'] === 0, 'profile counts default to zero');
check(array_keys($profile) === ['id', 'displayName', 'username', 'avatarUrl', 'bio', 'coverUrl', 'isAdmin', 'isModerator', 'createdAt', 'followerCount', 'followingCount', 'reelCount', 'isFollowing', 'isSelf'], 'profile field allowlist');

$GLOBALS['social_queries'] = [];
$GLOBALS['social_user_row'] = [
    'id' => 42,
    'username' => 'jeric',
    'display_name' => 'Jeric',
    'avatar_url' => null,
    'created_at' => '2026-01-01 00:00:00',
    'is_admin' => 0,
    'is_moderator' => 0,
    'deleted_at' => null,
    'is_banned' => 0,
];
$shown = users_show(['params' => ['id' => '42'], 'user' => ['id' => '42']]);
check($shown['user']['followerCount'] === 12 && $shown['user']['followingCount'] === 7 && $shown['user']['reelCount'] === 3, 'profile route uses directional counts');
check($shown['user']['isSelf'] === true, 'profile route marks self');
$countSql = implode(' ', array_column($GLOBALS['social_queries'], 'sql'));
check(str_contains($countSql, 'WHERE f.creator_id') && str_contains($countSql, 'WHERE f.follower_id'), 'follower and following predicates are exercised');

$GLOBALS['social_user_row']['deleted_at'] = '2026-01-02 00:00:00';
api_error(fn () => users_show(['params' => ['id' => '42'], 'user' => ['id' => '42']]), 404, 'deleted profile route returns 404');
$GLOBALS['social_user_row']['deleted_at'] = null;
$GLOBALS['social_user_row']['is_banned'] = 1;
api_error(fn () => users_show(['params' => ['id' => '42'], 'user' => ['id' => '42']]), 404, 'banned profile route returns 404');
$GLOBALS['social_user_row']['is_banned'] = 0;

$GLOBALS['social_queries'] = [];
$GLOBALS['social_reel_rows'] = [[
    'id' => 'reel-1',
    'caption' => 'hello',
    'poster_url' => 'https://example.com/reel-1.jpg',
    'created_at' => '2026-01-01 00:00:00',
]];
$GLOBALS['social_reel_media_rows'] = [[
    'reel_id' => 'reel-1',
    'position' => 1,
    'image_url' => 'https://example.com/reel-1.jpg',
    'width' => 100,
    'height' => 200,
]];
$reels = users_reels(['params' => ['id' => '42'], 'query' => ['limit' => '999', 'offset' => '2']]);
check(count($reels['reels']) === 1 && $reels['nextOffset'] === 3, 'creator reels route maps visible rows');
check(isset($reels['reels'][0]['images']) && !isset($reels['reels'][0]['videoUrl']), 'creator reels map image carousel shape');
$reelQuery = null;
foreach ($GLOBALS['social_queries'] as $query) {
    if (str_contains($query['sql'], 'FROM app_reels')) {
        $reelQuery = $query;
        break;
    }
}
check($reelQuery !== null && str_contains($reelQuery['sql'], "status = 'visible'"), 'creator reels query filters visible status');
check($reelQuery !== null && str_contains($reelQuery['sql'], 'app_reel_media'), 'creator reels query requires visible media');
check($reelQuery !== null && str_contains($reelQuery['sql'], 'LIMIT 50 OFFSET 2'), 'creator reels pagination uses integer literals');
check($reelQuery !== null && $reelQuery['params'] === [42], 'creator reels query binds only user id');

$GLOBALS['social_queries'] = [];
$GLOBALS['social_reel_rows'] = [];
reels_feed(['query' => ['feed' => 'for-you', 'limit' => '10', 'offset' => '0'], 'user' => ['id' => '42']]);
$feedQuery = null;
foreach ($GLOBALS['social_queries'] as $query) {
    if (str_contains($query['sql'], 'FROM app_reels')) {
        $feedQuery = $query;
        break;
    }
}
check($feedQuery !== null && str_contains($feedQuery['sql'], 'LIMIT 10 OFFSET 0'), 'feed pagination uses integer literals');
check($feedQuery !== null && $feedQuery['params'] === ['42', '42'], 'feed binds viewer predicates only');
check($feedQuery !== null && substr_count($feedQuery['sql'], '?') === count($feedQuery['params']), 'feed placeholder count matches bound params');

$GLOBALS['social_queries'] = [];
reels_feed(['query' => ['feed' => 'following', 'limit' => '10', 'offset' => '0'], 'user' => ['id' => '42']]);
$followingFeedQuery = null;
foreach ($GLOBALS['social_queries'] as $query) {
    if (str_contains($query['sql'], 'FROM app_reels')) {
        $followingFeedQuery = $query;
        break;
    }
}
check($followingFeedQuery !== null && substr_count($followingFeedQuery['sql'], '?') === count($followingFeedQuery['params']), 'following feed placeholder count matches bound params');

$mappedReel = reel_social_map([
    'id' => 'reel-1',
    'user_id' => 42,
    'username' => 'jeric',
    'display_name' => 'Jeric',
    'is_admin' => 0,
    'is_moderator' => 0,
], '42');
check($mappedReel['creator']['id'] === '42', 'reel creator id uses user id');
check($mappedReel['id'] === 'reel-1', 'reel id remains reel id');

$GLOBALS['social_queries'] = [];
$GLOBALS['social_viewer_row'] = ['id' => 42, 'deleted_at' => null, 'is_banned' => 0];
$GLOBALS['social_user_row'] = ['id' => 43, 'deleted_at' => null, 'is_banned' => 0];
$GLOBALS['social_edge'] = null;
$followed = follows_add(['params' => ['id' => '43'], 'user' => ['id' => '42']]);
check($followed === ['ok' => true, 'isFollowing' => true, 'followerCount' => 12], 'follow response shape');
$followSql = implode(' ', array_column($GLOBALS['social_queries'], 'sql'));
check(str_contains($followSql, 'INSERT IGNORE INTO app_follows'), 'follow is idempotent');
$unfollowed = follows_remove(['params' => ['id' => '43'], 'user' => ['id' => '42']]);
check($unfollowed === ['ok' => true, 'isFollowing' => false, 'followerCount' => 12], 'unfollow response shape');
$GLOBALS['social_user_row'] = ['id' => 42, 'deleted_at' => null, 'is_banned' => 0];
api_error(fn () => follows_add(['params' => ['id' => '42'], 'user' => ['id' => '42']]), 400, 'self follow rejected');
$GLOBALS['social_user_row'] = null;
api_error(fn () => follows_add(['params' => ['id' => '43'], 'user' => ['id' => '42']]), 404, 'missing follow target rejected');
$GLOBALS['social_user_row'] = ['id' => 43, 'deleted_at' => null, 'is_banned' => 1];
api_error(fn () => follows_add(['params' => ['id' => '43'], 'user' => ['id' => '42']]), 404, 'banned follow target rejected');
$GLOBALS['social_user_row'] = ['id' => 43, 'deleted_at' => null, 'is_banned' => 0];
$GLOBALS['social_queries'] = [];
$followers = follows_list(['params' => ['id' => '43'], 'query' => ['limit' => '999', 'offset' => '2']], 'followers');
check($followers['nextOffset'] === 2, 'follower list response shape');
$followerQuery = null;
foreach ($GLOBALS['social_queries'] as $query) {
    if (str_contains($query['sql'], 'FROM app_follows')) {
        $followerQuery = $query;
        break;
    }
}
check($followerQuery !== null && $followerQuery['params'] === [43, 50, 2], 'follower list clamps pagination');
api_error(fn () => follows_list(['params' => ['id' => '43'], 'query' => []], 'invalid'), 400, 'invalid social list direction rejected');

$followAccount = (string) file_get_contents(__DIR__ . '/../routes/account.php');
check(str_contains($followAccount, 'DELETE FROM app_follows WHERE follower_id = ? OR creator_id = ?'), 'account deletion removes both follow directions');
$followSocial = (string) file_get_contents(__DIR__ . '/../lib/social.php');
check(str_contains($followSocial, 'JOIN ' . "' . T_USERS . '" . ' u ON u.id = f.follower_id'), 'follower counts exclude invisible users');
check(str_contains($followSocial, 'JOIN ' . "' . T_USERS . '" . ' u ON u.id = f.creator_id'), 'following counts exclude invisible users');
$followRoute = (string) file_get_contents(__DIR__ . '/../routes/follows.php');
check(str_contains($followRoute, 'beginTransaction') && str_contains($followRoute, 'FOR UPDATE'), 'follow mutations lock participants in a transaction');
check(str_contains($followRoute, "SELECT 1 FROM app_follows WHERE follower_id = ? AND creator_id = ?"), 'follow response derives actual edge state');
check(is_file(__DIR__ . '/../../database/mobile_app_follow_cleanup.sql'), 'follow cleanup migration exists');

check(social_positive_id('42') === 42, 'positive integer id accepted');
api_error(fn () => social_positive_id('0'), 400, 'zero id rejected');
api_error(fn () => social_positive_id('-1'), 400, 'negative id rejected');
api_error(fn () => social_positive_id('42abc'), 400, 'non numeric id rejected');

check(social_pagination([]) === ['limit' => 20, 'offset' => 0], 'default pagination');
check(social_pagination(['limit' => '999', 'offset' => '5']) === ['limit' => 50, 'offset' => 5], 'limit clamps to 50');
check(social_pagination(['limit' => '0', 'offset' => '0']) === ['limit' => 1, 'offset' => 0], 'limit clamps to 1');
api_error(fn () => social_pagination(['offset' => '-1']), 400, 'negative offset rejected');
api_error(fn () => social_pagination(['limit' => 'nope']), 400, 'non numeric limit rejected');

$googlePhoto = 'https://lh3.googleusercontent.com/a/example=s96-c';
check(social_google_photo_url($googlePhoto) === $googlePhoto, 'Google HTTPS photo accepted');
check(social_google_photo_url(null) === null, 'missing photo accepted as null');
check(social_google_photo_url('') === null, 'empty photo rejected');
check(social_google_photo_url('http://lh3.googleusercontent.com/a/x') === null, 'HTTP photo rejected');
check(social_google_photo_url('https://evil.example/a/x') === null, 'foreign photo host rejected');
check(social_google_photo_url('https://user:pass@lh3.googleusercontent.com/a/x') === null, 'photo credentials rejected');
check(social_google_photo_url('https://lh3.googleusercontent.com/' . str_repeat('x', 1000)) === null, 'oversized photo rejected');

$authSource = (string) file_get_contents(__DIR__ . '/../lib/auth.php');
check(str_contains($authSource, 'if ($avatar !== null)'), 'invalid Google photo retains existing avatar');
check(str_contains($authSource, 'UPDATE ' . "' . T_USERS . '" . ' SET avatar_url = ?'), 'existing Google avatar is synced');

$report = social_report_validate([
    'targetType' => 'message',
    'targetId' => 'thread__message',
    'reason' => 'spam',
    'details' => '  Repeated ads  ',
    'snapshot' => '  Buy now  ',
    'threadId' => '10__2',
]);
check($report['snapshot'] === 'Buy now' && $report['details'] === 'Repeated ads', 'report text trimmed');
check($report['threadId'] === '10__2', 'report keeps verified thread context');
$reelReport = social_report_validate(['targetType' => 'reel', 'targetId' => 'r1', 'reason' => 'spam']);
check($reelReport['snapshot'] === 'Reported caption', 'reel report stores server-side caption snapshot');
$reelReportSql = $GLOBALS['social_queries'][array_key_last($GLOBALS['social_queries'])]['sql'] ?? '';
check(str_contains($reelReportSql, 'FROM app_reels r'), 'reel report lookup aliases reel table');
$commentReport = social_report_validate(['targetType' => 'comment', 'targetId' => 'c1', 'reason' => 'spam']);
check($commentReport['snapshot'] === 'Reported comment', 'comment report stores server-side text snapshot');
api_error(fn () => social_report_validate(['targetType' => 'message', 'targetId' => 'm1', 'reason' => 'spam']), 400, 'message report requires snapshot');
api_error(fn () => social_report_validate(['targetType' => 'message', 'targetId' => 'm1', 'reason' => 'spam', 'snapshot' => 'hello']), 400, 'message report requires thread context');
api_error(fn () => social_report_validate(['targetType' => 'message', 'targetId' => 'm1', 'reason' => 'spam', 'snapshot' => 'hello', 'threadId' => '../bad']), 400, 'invalid thread id rejected');
api_error(fn () => social_report_validate(['targetType' => 'message', 'targetId' => 'm1', 'reason' => 'spam', 'snapshot' => '   ']), 400, 'blank snapshot rejected');
api_error(fn () => social_report_validate(['targetType' => 'user', 'targetId' => '42', 'reason' => 'unknown']), 400, 'unknown report reason rejected');
api_error(fn () => social_report_validate(['targetType' => 'group', 'targetId' => '42', 'reason' => 'spam']), 400, 'unknown target type rejected');
api_error(fn () => social_report_validate(['targetType' => 'user', 'targetId' => '', 'reason' => 'spam']), 400, 'empty target rejected');
api_error(fn () => social_report_validate(['targetType' => 'message', 'targetId' => 'm1', 'reason' => 'spam', 'snapshot' => str_repeat('x', 501)]), 400, 'oversized snapshot rejected');

$firebaseSource = (string) file_get_contents(__DIR__ . '/../lib/firebase.php');
check(str_contains($firebaseSource, 'function firebase_scrub_social(string $uid): bool'), 'social scrub helper reports completion');
check(str_contains($firebaseSource, 'function firebase_delete_user(string $uid): void'), 'Firebase auth delete helper exists');
check(str_contains($firebaseSource, 'if (!firebase_enabled()) return;'), 'social cleanup is feature-gated');
check(str_contains($firebaseSource, 'identitytoolkit.googleapis.com/v1/projects/'), 'auth deletion uses Identity Toolkit');
check(substr_count($firebaseSource, 'catch (Throwable $e)') >= 3, 'cleanup helpers catch failures instead of throwing');

$accountSource = (string) file_get_contents(__DIR__ . '/../routes/account.php');
check(str_contains($accountSource, 'firebase_delete_user($uid)'), 'account deletion revokes Firebase auth');
check(str_contains($accountSource, "DELETE FROM app_reports WHERE reporter_id = ? OR (target_type = 'user' AND target_id = ?)"), 'account deletion removes authored and user-target reports');
check(str_contains($accountSource, 'avatar_url = NULL'), 'account deletion blanks the Google avatar');
check(str_contains($accountSource, "DELETE FROM feedbacks WHERE user_id = ? AND source = 'app'"), 'account deletion removes only private app feedback');
check(str_contains($accountSource, 'app_cleanup_queue'), 'social cleanup is queued for a durable worker');
check(is_file(__DIR__ . '/../cleanup_social.php'), 'social cleanup cron worker exists');

$rulesPath = getenv('GHOSST_RULES_FILE') ?: __DIR__ . '/../../../firestore.rules';
$rules = is_file($rulesPath) ? (string) file_get_contents($rulesPath) : '';
check(str_contains($rules, 'match /user_inboxes/{uid}/threads/{threadId}'), 'inbox pointers have scoped rules');
check(str_contains($rules, 'getAfter('), 'batched first writes validate projected state');
check(str_contains($rules, 'allow get: if signedIn()'), 'thread reads use block-aware document gets');
check(str_contains($rules, "!('replyText' in request.resource.data)"), 'world-chat reply text is validated independently');

$usersSource = (string) file_get_contents(__DIR__ . '/../routes/users.php');
check(str_contains($usersSource, 'function users_show(array $ctx): array'), 'safe user-by-id route exists');
$indexSource = (string) file_get_contents(__DIR__ . '/../index.php');
check(str_contains($indexSource, "'#^/v1/users/(\\d+)\$#'"), 'user-by-id route is registered');
check(str_contains($indexSource, "'#^/v1/users/(\\d+)/reels\$#'"), 'creator reels route is registered');

$reportsSource = (string) file_get_contents(__DIR__ . '/../routes/reports.php');
check(str_contains($reportsSource, 'FOR UPDATE'), 'report quota check is serialized per reporter');
check(str_contains($reportsSource, 'firebase_private_message'), 'message reports verify conversation participation');
check(str_contains($reportsSource, 'INSERT INTO app_reports'), 'report insert failures are not silently ignored');

check(social_feedback_is_public(['source' => 'app', 'status' => 'visible']) === false, 'app feedback is never public');
check(social_feedback_is_public(['status' => 'visible']) === true, 'legacy feedback defaults to public website source');
check(social_feedback_is_public(['source' => 'website', 'status' => 'hidden']) === false, 'hidden website feedback is not public');
$publicFeedback = (string) file_get_contents(__DIR__ . '/../../feedback.php');
$landingPage = (string) file_get_contents(__DIR__ . '/../../index.php');
$adminFeedback = (string) file_get_contents(__DIR__ . '/../../admin/feedbacks.php');
check(str_contains($publicFeedback, "source = 'website'"), 'public feedback page filters website source');
check(str_contains($landingPage, "source = 'website'"), 'landing page filters website source');
check(str_contains($adminFeedback, 'social_feedback_is_public'), 'admin show action guards app feedback');

check(feedback_validate(str_repeat('x', 9), 5) !== null, 'short feedback rejected');
check(feedback_validate(str_repeat('x', 10), 5) === null, 'minimum feedback accepted');
check(feedback_validate(str_repeat('x', 1000), 1) === null, 'maximum feedback accepted');
check(feedback_validate(str_repeat('x', 1001), 1) !== null, 'oversized feedback rejected');
check(feedback_validate("   \n", 5) !== null, 'blank feedback rejected');
check(feedback_validate('<script>bad</script>', 5) !== null, 'HTML feedback rejected');
check(feedback_validate('Valid feedback', 0) !== null, 'zero rating rejected');
check(feedback_validate('Valid feedback', 6) !== null, 'oversized rating rejected');
check(feedback_rating(3) === 3 && feedback_rating('3') === null && feedback_rating(3.5) === null, 'rating must be an integer');
check(feedback_account_active(['deleted_at' => null, 'is_banned' => 0]) === true, 'active account can submit feedback');
check(feedback_account_active(['deleted_at' => '2026-01-01', 'is_banned' => 0]) === false, 'deleted account cannot submit feedback');
check(feedback_account_active(['deleted_at' => null, 'is_banned' => 1]) === false, 'banned account cannot submit feedback');
$window = strtotime(feedback_window_start() . ' UTC');
check(abs(time() - 86400 - $window) <= 2, 'feedback quota uses rolling 24 hour UTC window');
$feedbackSource = (string) file_get_contents(__DIR__ . '/../routes/feedback.php');
check(str_contains($feedbackSource, "'app'") && str_contains($feedbackSource, "'hidden'"), 'app feedback is inserted private');
check(str_contains($feedbackSource, 'FOR UPDATE'), 'feedback quota check is serialized');
check(str_contains($feedbackSource, 'feedback_account_active'), 'feedback submission checks account state');
check(str_contains($feedbackSource, 'idem_reserve') && str_contains($feedbackSource, 'idem_complete'), 'feedback submission is idempotent');
check(str_contains($feedbackSource, 'idempotency-key'), 'feedback submission requires an idempotency key');
check(str_contains($indexSource, "'#^/v1/feedback$#'"), 'feedback submit route is registered');
check(str_contains($indexSource, "'#^/v1/feedback/mine$#'"), 'feedback history route is registered');

$accountRoute = (string) file_get_contents(__DIR__ . '/../routes/account.php');
$lockAt = strpos($accountRoute, 'FOR UPDATE');
$deleteAt = strpos($accountRoute, "DELETE FROM feedbacks");
check($lockAt !== false && $deleteAt !== false && $lockAt < $deleteAt, 'account deletion locks the user before deleting feedback');
$websiteSubmit = (string) file_get_contents(__DIR__ . '/../../ajax/submit_feedback.php');
check(str_contains($websiteSubmit, "source = 'website'"), 'website feedback quota excludes app feedback');
check(is_file(__DIR__ . '/../../database/mobile_app_avatar.sql'), 'avatar migration is split and rerunnable');
check(is_file(__DIR__ . '/../../database/mobile_app_feedback.sql'), 'feedback migration is split and rerunnable');
$socialUsersMigration = (string) file_get_contents(__DIR__ . '/../../database/mobile_app_social_users.sql');
check(str_contains($socialUsersMigration, '`is_moderator`'), 'shared users moderator migration exists');
$socialMigration = (string) file_get_contents(__DIR__ . '/../../database/mobile_app_social.sql');
check(!str_contains($socialMigration, 'ADD COLUMN `avatar_url`') && !str_contains($socialMigration, 'ADD COLUMN `source`'), 'cumulative social migration contains only rerunnable table creates');
check(str_contains($publicFeedback, "source      ENUM('website','app')"), 'feedback fallback schema includes source');

$claims = [
    'sub' => '42',
    'reelId' => 'r1',
    'purpose' => 'reel-upload',
    'sha256' => str_repeat('a', 64),
    'sizeBytes' => 123,
];
$ticket = reel_ticket_sign($claims);
$verified = reel_ticket_verify($ticket, 'reel-upload');
check($verified !== null && $verified['reelId'] === 'r1' && $verified['sizeBytes'] === 123, 'valid reel ticket verifies');
check(reel_ticket_verify($ticket, 'reel-delete') === null, 'wrong ticket purpose rejected');
check(reel_ticket_verify(reel_ticket_sign($claims, -1), 'reel-upload') === null, 'expired ticket rejected');
check(reel_ticket_verify(reel_ticket_sign(['sub' => '42', 'purpose' => 'reel-upload']), 'reel-upload') === null, 'incomplete ticket rejected');
$imageTicket = reel_ticket_sign([
    'sub' => '42',
    'reelId' => 'r1',
    'position' => 1,
    'purpose' => 'reel-image-upload',
    'sha256' => str_repeat('a', 64),
    'sizeBytes' => 123,
    'mimeType' => 'image/jpeg',
    'ext' => 'jpg',
]);
$verifiedImage = reel_ticket_verify($imageTicket, 'reel-image-upload');
check(is_array($verifiedImage) && $verifiedImage['position'] === 1 && $verifiedImage['mimeType'] === 'image/jpeg', 'image ticket verifies');
$parts = explode('.', $ticket);
$tamperedBody = rtrim(strtr(base64_decode($parts[1]), '+/', '-_'), '=');
$decoded = json_decode($tamperedBody, true);
$decoded['sizeBytes'] = 999;
$tampered = $parts[0] . '.' . rtrim(strtr(base64_encode(json_encode($decoded)), '+/', '-_'), '=') . '.' . $parts[2];
check(reel_ticket_verify($tampered, 'reel-upload') === null, 'tampered ticket rejected');
$wrongSecret = rtrim(strtr(base64_encode(json_encode(['alg' => 'HS256', 'typ' => 'JWT'])), '+/', '-_'), '=') . '.' . $tamperedBody . '.' . rtrim(strtr(base64_encode(hash_hmac('sha256', $parts[0] . '.' . $tamperedBody, 'wrong-secret', true)), '+/', '-_'), '=');
check(reel_ticket_verify($wrongSecret, 'reel-upload') === null, 'wrong ticket secret rejected');
check(idem_hash_matches(null, null) === true && idem_hash_matches('abc', 'abc') === true && idem_hash_matches('abc', 'def') === false, 'idempotency request hash mismatch is detectable');

check(reel_comment_validate('') !== null && reel_comment_validate('   ') !== null, 'blank reel comment rejected');
check(reel_comment_validate(str_repeat('x', 500)) === null, 'maximum reel comment accepted');
check(reel_comment_validate(str_repeat('x', 501)) !== null, 'oversized reel comment rejected');
$reelSocial = (string) file_get_contents(__DIR__ . '/../routes/reel_social.php');
check(str_contains($reelSocial, "r.status = 'visible'"), 'reel feed filters visible reels');
check(str_contains($reelSocial, 'u.deleted_at IS NULL') && str_contains($reelSocial, 'u.is_banned = 0'), 'reel feed excludes invisible creators');
check(str_contains($reelSocial, 'FROM app_follows'), 'following feed joins follow graph');
check(str_contains($reelSocial, 'INSERT IGNORE INTO app_reel_likes'), 'reel likes are idempotent');
check(str_contains($reelSocial, '30'), 'comment rate limit is enforced');

$GLOBALS['social_queries'] = [];
$GLOBALS['social_json_body'] = ['text' => 'hi'];
$GLOBALS['social_user_row'] = ['id' => 42, 'deleted_at' => null, 'is_banned' => 0];
$commentResult = reels_comments_create(['params' => ['id' => 'r1'], 'user' => ['id' => '42']]);
check(($commentResult['commentId'] ?? '') !== '', 'comment creation succeeds for visible reel');
$commentReelQuery = null;
foreach ($GLOBALS['social_queries'] as $query) {
    if (str_contains($query['sql'], 'SELECT id FROM app_reels')) {
        $commentReelQuery = $query;
        break;
    }
}
check($commentReelQuery !== null && str_contains($commentReelQuery['sql'], 'FROM app_reels r'), 'comment creation aliases reel table');

$adminReels = (string) file_get_contents(__DIR__ . '/../routes/admin_reels.php');
check(str_contains($adminReels, 'require_moderator'), 'reel moderation requires a moderator');
$dbConfig = (string) file_get_contents(__DIR__ . '/../../includes/db_config.php');
check(str_contains($dbConfig, "(\$user['role'] ?? '') === 'admin'"), 'social moderator accepts website admins');
check(str_contains($dbConfig, "(\$user['is_admin'] ?? 0) === 1") && str_contains($dbConfig, "(\$user['is_moderator'] ?? 0) === 1"), 'social moderator accepts app admin/moderator flags');
$adminPage = (string) file_get_contents(__DIR__ . '/../../admin/reels.php');
check(str_contains($adminPage, 'requireSocialModerator()'), 'moderation page uses social guard');
check(str_contains($adminPage, 'verifyCsrf('), 'moderation page verifies CSRF');
check(str_contains($adminPage, "'reel_status'") && str_contains($adminPage, "'comment_status'") && str_contains($adminPage, "'report_status'") && str_contains($adminPage, '$statusAliases[$action][$rawStatus]'), 'moderation actions and statuses are allowlisted');
check(str_contains($adminPage, 'htmlspecialchars($reel[\'caption\']') && str_contains($adminPage, 'htmlspecialchars((string) $report[\'content_snapshot\']'), 'captions and report snapshots are escaped');

$GLOBALS['social_idem_key'] = 'complete-key';
$GLOBALS['social_fake_db']->idemRows = [];
$_GET = [];
$GLOBALS['social_reel_status'] = 'pending';
$GLOBALS['social_reel_media_rows'] = [
    ['position' => 1, 'image_url' => null, 'storage_key' => 'r1-1.jpg', 'sha256' => str_repeat('a', 64), 'size_bytes' => 123, 'mime_type' => 'image/jpeg', 'status' => 'pending'],
];
$GLOBALS['social_json_body'] = ['images' => [['position' => 1, 'imageUrl' => 'https://video.example/media/r1-1.jpg', 'sha256' => str_repeat('a', 64), 'sizeBytes' => 123]]];
$GLOBALS['social_queries'] = [];
$result = reels_upload_complete(['params' => ['id' => 'r1'], 'user' => ['id' => '42']]);
check($result['reel']['status'] === 'visible', 'image completion marks reel visible');
$GLOBALS['social_reel_status'] = 'visible';
$replay = reels_upload_complete(['params' => ['id' => 'r1'], 'user' => ['id' => '42']]);
check($replay['reel']['status'] === 'visible', 'image completion replay remains successful');
$GLOBALS['social_json_body'] = ['images' => [['position' => 1, 'imageUrl' => 'https://video.example/media/r1-1.jpg', 'sha256' => str_repeat('b', 64), 'sizeBytes' => 123]]];
api_error(fn() => reels_upload_complete(['params' => ['id' => 'r1'], 'user' => ['id' => '42']]), 409, 'image completion payload mismatch');

$accountDelete = (string) file_get_contents(__DIR__ . '/../routes/account.php');
check(str_contains($accountDelete, 'SELECT id FROM app_reels WHERE user_id = ?'), 'account deletion collects reel ids before anonymizing');
check(str_contains($accountDelete, 'DELETE FROM app_reel_likes') && str_contains($accountDelete, 'DELETE FROM app_reel_comments') && str_contains($accountDelete, 'DELETE FROM app_reel_media') && str_contains($accountDelete, 'DELETE FROM app_reels'), 'account deletion removes reel social rows');
check(str_contains($accountDelete, 'DELETE FROM app_reports WHERE reporter_id = ? OR (target_type = \'user\' AND target_id = ?)'), 'account deletion removes authored and user-target reports');
check(str_contains($accountDelete, '$pdo->commit();') && strpos($accountDelete, 'reels_delete_files($reelIds)') > strpos($accountDelete, '$pdo->commit();'), 'hosted reel files are deleted only after database commit');
$reelLib = (string) file_get_contents(__DIR__ . '/../lib/reels.php');
check(str_contains($reelLib, 'function reels_delete_files(array $reelIds): void'), 'hosted deletion helper exists');
$reelLib = (string) file_get_contents(__DIR__ . '/../lib/reels.php');
check(str_contains($reelLib, "foreach (\$ids as \$reelId)") && str_contains($reelLib, "'reelId' => \$reelId") && str_contains($reelLib, 'curl_exec($ch)'), 'hosted deletion binds and sends one ticket per reel');
check(str_contains($reelLib, 'catch (Throwable'), 'hosted deletion failures never escape');

$uploadHandler = (string) file_get_contents(__DIR__ . '/../../reels/upload.php');
check(str_contains($uploadHandler, '$_FILES[\'video\']') && str_contains($uploadHandler, 'is_uploaded_file') && str_contains($uploadHandler, "hash_file('sha256'"), 'uploader validates multipart bytes instead of raw request body');
check(str_contains($uploadHandler, 'file_exists($destination)') && str_contains($uploadHandler, "hash_file('sha256', \$destination)"), 'identical upload replay returns the existing media');
$reelRoutes = (string) file_get_contents(__DIR__ . '/../routes/reels.php');
check(str_contains($reelRoutes, 'idempotency-key') && str_contains($reelRoutes, 'reels_upload_complete_locked'), 'completion is idempotent and serialized');
$apiIndex = (string) file_get_contents(__DIR__ . '/../index.php');
check(str_contains($apiIndex, "require __DIR__ . '/lib/reels.php';"), 'API front controller loads reel helpers');
check(str_contains($reelRoutes, 'social_require_visible_reel') || str_contains($reelSocial, 'reel_visible_where('), 'reel interactions require visible content and creator');
check(str_contains($reelSocial, 'FOR UPDATE') && str_contains($reelSocial, 'created_at >='), 'comment quota is serialized');
$cleanup = (string) file_get_contents(__DIR__ . '/../cleanup_social.php');
check(str_contains($cleanup, 'reels_delete_files($expiredIds)') && str_contains($cleanup, "SET status = 'deleted'"), 'pending upload expiry deletes metadata and media');
$currentUser = substr($dbConfig, strpos($dbConfig, 'function currentUser'));
check(str_contains($currentUser, 'is_admin') && str_contains($currentUser, 'is_moderator'), 'website session loads app moderator flags');
$apiAuth = (string) file_get_contents(__DIR__ . '/../lib/auth.php');
check(str_contains($apiAuth, "strtolower((string) (\$row['role'] ?? '')) === 'admin'"), 'API treats website admins as app admins');
$deleteHost = (string) file_get_contents(__DIR__ . '/../../reels/delete.php');
check(str_contains($deleteHost, "claims['reelId']") && str_contains($deleteHost, '$ids[0]'), 'delete ticket is bound to its manifest');

$GLOBALS['social_comment_rows'] = [[
    'id' => 'c1',
    'text' => 'Nice',
    'created_at' => '2026-11-26 10:00:00',
    'user_id' => 651,
    'username' => 'cankillyou',
    'display_name' => 'Can Kill You',
]];
$commentList = reels_comments_list(['params' => ['id' => 'r1'], 'query' => []]);
check(
    ($commentList['comments'][0]['user']['id'] ?? '') === '651',
    'comment payload carries the commenter id'
);

echo "ok\n";
