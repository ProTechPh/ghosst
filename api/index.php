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
require __DIR__ . '/lib/cloudinary.php';
require __DIR__ . '/lib/push.php';

foreach (glob(__DIR__ . '/routes/*.php') ?: [] as $file) {
    require $file;
}

/** @var array<int,array{0:string,1:string,2:string,3:string}> */
const ROUTES = [
    ['POST',   '#^/v1/auth/register$#',                    'auth_register',           'none'],
    ['POST',   '#^/v1/auth/login$#',                       'auth_login',              'none'],
    ['POST',   '#^/v1/auth/refresh$#',                     'auth_refresh',            'none'],
    ['POST',   '#^/v1/auth/logout$#',                      'auth_logout',             'required'],

    ['GET',    '#^/v1/me$#',                               'account_me',              'required'],
    ['GET',    '#^/v1/wallet$#',                           'account_wallet',          'required'],
    ['DELETE', '#^/v1/account$#',                          'account_remove',          'required'],

    ['GET',    '#^/v1/products$#',                         'products_list',           'optional'],
    ['GET',    '#^/v1/products/([\w.-]+)$#',               'products_get',            'optional'],
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
    ['POST',   '#^/v1/admin/announcements$#',              'announcements_create',    'required'],

    ['POST',   '#^/v1/uploads/presign$#',                  'uploads_presign',         'required'],
    ['POST',   '#^/v1/uploads/complete$#',                 'uploads_complete',        'required'],

    ['GET',    '#^/v1/downloads/([\w.-]+)$#',              'downloads_ticket',        'required'],

    // Si Google ang tumatawag dito: walang JWT, signature ang verification.
    ['GET',    '#^/v1/ads/ssv$#',                          'ads_ssv',                 'none'],
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
    'params'    => ['id' => $match[1] ?? ''],
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

    $result = ($route[2])($ctx);

    if ($result instanceof RawResponse) {
        send_response($result->status, $result->body, $result->contentType);
        exit;
    }

    // Public product reads ay safe i-cache; may auth ay hindi.
    if ($method === 'GET' && str_starts_with($path, '/v1/products') && header_value('authorization') === '') {
        header('cache-control: public, max-age=30, stale-while-revalidate=120');
    }

    send_response(200, json_encode_body($result), 'application/json; charset=utf-8');
} catch (ApiError $e) {
    send_error($e, $requestId);
} catch (Throwable $e) {
    log_line($requestId, $method . ' ' . $path . ' — ' . $e->getMessage());
    send_response(
        500,
        json_encode_body(['ok' => false, 'error' => [
            'code'      => internal_error_code($e),
            'message'   => 'Something went wrong on our side',
            'requestId' => $requestId,
        ]]),
        'application/json; charset=utf-8'
    );
}
