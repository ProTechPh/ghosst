<?php
declare(strict_types=1);

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

require __DIR__ . '/../lib/uploads.php';

check(
    delete_stored_image('https://res.cloudinary.com/zp6uwlrj/image/upload/a.jpg') === false,
    'foreign URL is not deleted'
);
check(delete_stored_image('../config.php') === false, 'parent path is rejected');

echo "ok\n";
