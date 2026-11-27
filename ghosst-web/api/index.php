<?php
/**
 * Front controller ng mobile API.
 *
 * Parehong contract ng Cloudflare Worker (cf-ghosst/src/index.ts): parehong
 * paths, parehong JSON envelope, parehong error codes. Ang app ay walang
 * babaguhin maliban sa API_BASE_URL.
 */

declare(strict_types=1);

ini_set('display_errors', '0');
error_reporting(E_ALL);

require __DIR__ . '/config.php';
require __DIR__ . '/lib/http.php';
require __DIR__ . '/lib/db.php';
require __DIR__ . '/lib/auth.php';
require __DIR__ . '/lib/idempotency.php';
require __DIR__ . '/lib/rewards.php';
require __DIR__ . '/lib/push.php';
require __DIR__ . '/lib/firebase.php';
require __DIR__ . '/lib/social.php';
require __DIR__ . '/lib/reels.php';
require __DIR__ . '/lib/integrity.php';

foreach (glob(__DIR__ . '/routes/*.php') ?: [] as $file) {
    require $file;
}

// A partial upload (missing or stale lib file) used to fatal somewhere below
// with "Call to undefined function ...". Fail with a clear, loggable 503 and
// redeploy the whole api/ folder.
foreach ([
    'header_value', 'uuid4', 'json_encode_body', 'one', 'all_rows',
    'scalar', 'run_sql', 'require_user',
] as $requiredFn) {
    if (!function_exists($requiredFn)) {
        error_log('Deploy incomplete: missing ' . $requiredFn . '()');
        http_response_code(503);
        header('content-type: application/json; charset=utf-8');
        echo '{"ok":false,"error":{"code":"deployment_incomplete",'
            . '"message":"API deploy is incomplete — re-upload the api/ folder"}}';
        exit;
    }
}

/** @var array<int,array{0:string,1:string,2:string,3:string}> */
const ROUTES = [
    ['POST',   '#^/v1/auth/register$#',                    'auth_register',           'none'],
    ['POST',   '#^/v1/auth/login$#',                       'auth_login',              'none'],
    ['POST',   '#^/v1/auth/google$#',                      'auth_google',             'none'],
    ['POST',   '#^/v1/auth/refresh$#',                     'auth_refresh',            'none'],
    ['POST',   '#^/v1/auth/logout$#',                      'auth_logout',             'required'],

    ['GET',    '#^/v1/me$#',                               'account_me',              'required'],
    ['POST',   '#^/v1/me/referral$#',                      'me_claim_referral',       'required'],
    ['GET',    '#^/v1/wallet$#',                           'account_wallet',          'required'],
    ['DELETE', '#^/v1/account$#',                          'account_remove',          'required'],
    ['GET',    '#^/v1/firebase/token$#',                   'account_firebase_token',  'required'],

    ['GET',    '#^/v1/products$#',                         'products_list',           'optional'],
    ['GET',    '#^/v1/products/([\w.-]+)$#',               'products_get',            'optional'],
    ['GET',    '#^/v1/premium-shop$#',                     'premium_shop_list',       'none'],
    ['GET',    '#^/v1/premium-shop/(\d+)$#',               'premium_shop_product',    'none'],
    ['POST',   '#^/v1/products$#',                         'products_create',         'required'],
    ['PATCH',  '#^/v1/products/([\w.-]+)$#',               'products_update',         'required'],
    ['DELETE', '#^/v1/products/([\w.-]+)$#',               'products_remove',         'required'],

    ['POST',   '#^/v1/admin/keys$#',                       'keys_add',                'required'],
    ['GET',    '#^/v1/admin/keys$#',                       'keys_list',               'required'],
    ['DELETE', '#^/v1/admin/keys/([\w.-]+)$#',             'keys_remove',             'required'],
    ['DELETE', '#^/v1/admin/products/([\w.-]+)/keys$#',    'keys_clear_for_product',  'required'],

    ['POST',   '#^/v1/claims$#',                           'claims_claim',            'required'],
    ['GET',    '#^/v1/claims$#',                           'claims_list',             'required'],

    ['GET',    '#^/v1/announcements$#',                    'announcements_latest',    'required'],
    ['GET',    '#^/v1/announcements/history$#',            'announcements_list',      'required'],
    ['POST',   '#^/v1/admin/announcements$#',              'announcements_create',    'required'],
    ['DELETE', '#^/v1/admin/announcements/([\w.-]+)$#',    'announcements_delete',    'required'],
    ['POST',   '#^/v1/admin/chat/mute$#',                  'chat_mute_user',          'required'],
    ['GET',    '#^/v1/admin/chat/muted$#',                 'chat_muted_list',         'required'],
    ['GET',    '#^/v1/admin/moderators$#',                 'moderators_list',         'required'],
    ['GET',    '#^/v1/admin/users$#',                      'admin_users_search',      'required'],
    ['POST',   '#^/v1/admin/moderators/([\w.-]+)$#',       'moderator_promote',       'required'],
    ['DELETE', '#^/v1/admin/moderators/([\w.-]+)$#',       'moderator_demote',        'required'],
    ['GET',    '#^/v1/admin/banned-words$#',               'banned_words_list',       'required'],
    ['POST',   '#^/v1/admin/banned-words$#',               'banned_word_add',         'required'],
    ['DELETE', '#^/v1/admin/banned-words/([\w.-]+)$#',     'banned_word_remove',      'required'],
    ['GET',    '#^/v1/admin/moderation$#',                 'moderation_get',          'required'],
    ['POST',   '#^/v1/admin/moderation$#',                 'moderation_save',         'required'],

    ['POST',   '#^/v1/uploads/presign$#',                  'uploads_presign',         'required'],
    ['POST',   '#^/v1/uploads/complete$#',                 'uploads_complete',        'required'],
    ['POST',   '#^/v1/uploads/product-image$#',            'uploads_product_image',   'required'],
    ['POST',   '#^/v1/uploads/cover$#',                    'uploads_cover_image',     'required'],

    ['GET',    '#^/v1/downloads/([\w.-]+)$#',              'downloads_ticket',        'required'],

    // Si Google ang tumatawag dito: walang JWT, signature ang verification.
    ['GET',    '#^/v1/ads/ssv$#',                          'ads_ssv',                 'none'],
    // Remaining reward budget — app-side "daily limit reached".
    ['GET',    '#^/v1/ads/status$#',                       'ads_status',              'required'],
    // Play Integrity token decode — observe-only, never blocks.
    ['POST',   '#^/v1/integrity/check$#',                  'integrity_check',         'required'],
    // Force-update gate — public, needed before sign-in.
    ['GET',    '#^/v1/app/config$#',                       'app_config',              'none'],
    // Read markers (announcements + chat) — cross-device.
    ['GET',    '#^/v1/reads$#',                            'reads_get',               'required'],
    ['POST',   '#^/v1/reads$#',                            'reads_mark',              'required'],
    ['GET',    '#^/v1/users/search$#',                     'users_search',            'required'],
    ['POST',   '#^/v1/users/summaries$#',                  'users_summaries',         'required'],
    ['GET',    '#^/v1/users/(\d+)$#',                      'users_show',              'required'],
    ['POST',   '#^/v1/me/profile$#',                       'users_update_bio',        'required'],
    ['GET',    '#^/v1/users/(\d+)/reels$#',                'users_reels',             'required'],
    ['POST',   '#^/v1/users/(\d+)/follow$#',               'follows_add',             'required'],
    ['DELETE', '#^/v1/users/(\d+)/follow$#',               'follows_remove',          'required'],
    ['GET',    '#^/v1/users/(\d+)/followers$#',            'follows_followers',       'required'],
    ['GET',    '#^/v1/users/(\d+)/following$#',            'follows_following',       'required'],
    ['POST',   '#^/v1/reports$#',                          'reports_create',          'required'],
    ['POST',   '#^/v1/feedback$#',                         'feedback_create',         'required'],
    ['POST',   '#^/v1/reels/uploads$#',                    'reels_upload_init',       'required'],
    ['POST',   '#^/v1/reels/([\w-]+)/complete$#',          'reels_upload_complete',   'required'],
    ['DELETE', '#^/v1/reels/([\w-]+)$#',                   'reels_delete',            'required'],
    ['GET',    '#^/v1/reels$#',                             'reels_feed',              'required'],
    ['GET',    '#^/v1/reels/([\w-]+)$#',                    'reels_show',              'required'],
    ['POST',   '#^/v1/reels/([\w-]+)/likes$#',              'reels_like',              'required'],
    ['DELETE', '#^/v1/reels/([\w-]+)/likes$#',              'reels_unlike',            'required'],
    ['GET',    '#^/v1/reels/([\w-]+)/comments$#',           'reels_comments_list',     'required'],
    ['POST',   '#^/v1/reels/([\w-]+)/comments$#',           'reels_comments_create',   'required'],
    ['DELETE', '#^/v1/reels/([\w-]+)/comments/([\w-]+)$#',  'reels_comments_delete',   'required'],
    ['GET',    '#^/v1/admin/reels$#',                       'admin_reels_list',        'required'],
    ['POST',   '#^/v1/admin/reels/([\w-]+)/status$#',       'admin_reels_set_status',  'required'],
    ['POST',   '#^/v1/admin/comments/([\w-]+)/status$#',    'admin_comments_set_status','required'],
    ['GET',    '#^/v1/admin/reports$#',                     'admin_reports_list',      'required'],
    ['POST',   '#^/v1/admin/reports/([\w-]+)/status$#',     'admin_reports_set_status','required'],
    ['GET',    '#^/v1/feedback/mine$#',                    'feedback_mine',           'required'],
    ['GET',    '#^/v1/feedback/public$#',                  'feedback_public',         'none'],
    // Website tutorials (public CMS content).
    ['GET',    '#^/v1/tutorials$#',                        'tutorials_list',          'none'],
    // Leaderboard — top coin holders.
    ['GET',    '#^/v1/leaderboard$#',                      'account_leaderboard',     'none'],
];

/** Kilalang server failure → code na kayang ipaliwanag ng app. */
function internal_error_code(Throwable $e): string
{
    $m = $e->getMessage();
    if (str_contains($m, 'max_user_connections') || str_contains($m, 'Too many connections')) {
        return 'server_busy';
    }
    if (str_contains($m, 'SQLSTATE[42S02]') || str_contains($m, 'Base table or view not found')) {
        return 'server_schema';
    }
    return 'internal';
}

function send_response(int $status, string $body, string $contentType): void
{
    http_response_code($status);
    header('content-type: ' . $contentType);
    header('x-request-id: ' . $GLOBALS['requestId']);
    echo $body;
}

function send_error(ApiError $e, string $requestId): void
{
    if ($e->retryAfter !== null) header('retry-after: ' . $e->retryAfter);
    send_response(
        $e->status,
        json_encode_body(['ok' => false, 'error' => [
            'code'      => $e->errorCode,
            'message'   => $e->getMessage(),
            'requestId' => $requestId,
        ]]),
        'application/json; charset=utf-8'
    );
}

$requestId = header_value('x-request-id');
if ($requestId === '') $requestId = uuid4();
$GLOBALS['requestId'] = $requestId;

$origin = header_value('origin');
$allowedOrigins = array_filter(array_map('trim', explode(',', ALLOWED_ORIGINS)));
if ($origin !== '') {
    if (in_array($origin, $allowedOrigins, true)) {
        header('access-control-allow-origin: ' . $origin);
        header('vary: origin');
    }
} else {
    header('access-control-allow-origin: *');
}
header('access-control-allow-methods: GET, POST, PATCH, DELETE, OPTIONS');
header('access-control-allow-headers: ' . (
    header_value('access-control-request-headers') ?: 'authorization, content-type, idempotency-key, x-request-id'
));
header('access-control-expose-headers: x-request-id, retry-after');
header('access-control-max-age: 86400');
header('x-content-type-options: nosniff');
header('x-frame-options: DENY');
header('referrer-policy: no-referrer');
header('strict-transport-security: max-age=31536000; includeSubDomains');
header('content-security-policy: default-src \'none\'; frame-ancestors \'none\'');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$path = parse_url((string) ($_SERVER['REQUEST_URI'] ?? '/'), PHP_URL_PATH) ?: '/';
$scriptDir = rtrim(str_replace('\\', '/', dirname((string) ($_SERVER['SCRIPT_NAME'] ?? ''))), '/');
if ($scriptDir !== '' && str_starts_with($path, $scriptDir)) {
    $path = substr($path, strlen($scriptDir));
}
// Fallback kapag walang mod_rewrite: /api/index.php/v1/...
if (str_starts_with($path, '/index.php')) {
    $path = substr($path, strlen('/index.php'));
}
$path = '/' . ltrim((string) $path, '/');
 
$method = (string) ($_SERVER['REQUEST_METHOD'] ?? 'GET');

// Device tracking: log every non-preflight request's origin (which hostname
// the client actually hit), client IP and User-Agent so we can see which
// networks/devices are failing and whether they reach mail. vs ghossthub.com.
// Goes to the PHP error log (Hostinger File Manager -> error_log).
if ($method !== 'OPTIONS') {
    error_log(sprintf(
        '[device] %s %s %s host=%s ip=%s ua=%s',
        gmdate('c'),
        $method,
        $path,
        (string) ($_SERVER['HTTP_HOST'] ?? ''),
        client_ip(),
        mb_substr((string) ($_SERVER['HTTP_USER_AGENT'] ?? ''), 0, 200, 'UTF-8')
    ));
}
$route = null;
foreach (ROUTES as $candidate) {
    if ($candidate[0] === $method && preg_match($candidate[1], $path, $match)) {
        $route = $candidate;
        break;
    }
}

if ($route === null) {
    send_response(
        404,
        json_encode_body(['ok' => false, 'error' => [
            'code'      => 'not_found',
            'message'   => 'No such route',
            'requestId' => $requestId,
        ]]),
        'application/json; charset=utf-8'
    );
    exit;
}

$ctx = [
    'params'    => ['id' => $match[1] ?? '', 'commentId' => $match[2] ?? ''],
    'query'     => $_GET,
    'user'      => null,
    'requestId' => $requestId,
];

try {
    if ($route[3] === 'required') {
        $ctx['user'] = require_user($ctx);
    } elseif ($route[3] === 'optional' && header_value('authorization') !== '') {
        try {
            $ctx['user'] = require_user($ctx);
        } catch (ApiError) {
            $ctx['user'] = null;
        }
    }

    if (!is_callable($route[2])) {
        // Usually a partial upload: the route table is newer than routes/*.php.
        log_line(
            $requestId,
            $method . ' ' . $path . ' — handler ' . $route[2] . '() is not loaded (stale deploy?)'
        );
        throw new ApiError(503, 'deployment_incomplete', 'This endpoint is not deployed yet');
    }

    $result = ($route[2])($ctx);

    if ($result instanceof RawResponse) {
        send_response($result->status, $result->body, $result->contentType);
        exit;
    }

    // Public product reads ay safe i-cache; may auth ay hindi.
    if ($method === 'GET' && str_starts_with($path, '/v1/leaderboard')) {
        header('cache-control: public, max-age=60, stale-while-revalidate=120');
    } elseif ($method === 'GET' && str_starts_with($path, '/v1/premium-shop') && header_value('authorization') === '') {
        header('cache-control: public, max-age=60, stale-while-revalidate=300');
    } elseif ($method === 'GET' && str_starts_with($path, '/v1/products') && header_value('authorization') === '') {
        header('cache-control: public, max-age=30, stale-while-revalidate=120');
    }

    send_response(200, json_encode_body($result), 'application/json; charset=utf-8');
} catch (ApiError $e) {
    send_error($e, $requestId);
} catch (Throwable $e) {
    log_line($requestId, $method . ' ' . $path . ' — ' . $e->getMessage());
    $code = internal_error_code($e);
    // Connection-cap failures are temporary: 503 + Retry-After so clients
    // back off instead of treating it as a hard 500.
    $status = $code === 'server_busy' ? 503 : 500;
    if ($status === 503) header('retry-after: 5');
    send_response(
        $status,
        json_encode_body(['ok' => false, 'error' => [
            'code'      => $code,
            'message'   => 'Something went wrong on our side',
            'requestId' => $requestId,
        ]]),
        'application/json; charset=utf-8'
    );
}
