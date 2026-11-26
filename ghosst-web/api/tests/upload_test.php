<?php
declare(strict_types=1);

if (!function_exists('mb_strlen')) {
    function mb_strlen(string $s, ?string $encoding = null): int { return strlen($s); }
}

require __DIR__ . '/../lib/http.php';

if (!function_exists('require_admin')) {
    function require_admin(array $ctx): array
    {
        $user = $ctx['user'] ?? null;
        if (!$user || !$user['isAdmin']) throw new ApiError(403, 'forbidden', 'Admin only');
        return $user;
    }
}

function check(bool $ok, string $label): void
{
    if (!$ok) {
        fwrite(STDERR, "FAIL: $label\n");
        exit(1);
    }
}

function api_error(callable $fn, int $status, string $code): void
{
    try {
        $fn();
    } catch (ApiError $e) {
        check($e->status === $status && $e->errorCode === $code, "$code ($status)");
        return;
    }
    check(false, "expected ApiError $code");
}

require __DIR__ . '/../routes/uploads.php';

$_FILES = [];
api_error(
    fn () => uploads_product_image(['user' => ['id' => '1', 'isAdmin' => true]]),
    400,
    'image_required'
);
api_error(
    fn () => uploads_product_image(['user' => ['id' => '1', 'isAdmin' => false]]),
    403,
    'forbidden'
);

if (!defined('PUBLIC_CDN')) define('PUBLIC_CDN', 'https://ghossthub.com');
require_once __DIR__ . '/../lib/uploads.php';

check(
    product_image_url('uploads/products/a.jpg') === 'https://ghossthub.com/uploads/products/a.jpg',
    'relative key becomes an absolute preview URL'
);
check(
    product_image_url('https://cdn.example/a.jpg') === 'https://cdn.example/a.jpg',
    'absolute URL passes through'
);
check(
    delete_stored_image('https://res.cloudinary.com/zp6uwlrj/image/upload/a.jpg') === false,
    'foreign URL is not deleted'
);
check(delete_stored_image('../config.php') === false, 'parent path is rejected');

check(profile_bio_validate('Hi there') === null, 'short plain bio is valid');
check(profile_bio_validate(str_repeat('a', 301)) !== null, 'long bio is rejected');
check(profile_bio_validate('Hello <b>world</b>') !== null, 'HTML in bio is rejected');
check(
    cover_image_url('uploads/covers/a.jpg') === 'https://ghossthub.com/uploads/covers/a.jpg',
    'cover key becomes an absolute URL'
);

echo "ok\n";
