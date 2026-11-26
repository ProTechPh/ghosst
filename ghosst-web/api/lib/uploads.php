<?php
declare(strict_types=1);

/** Tanggalin lang ang file sa loob ng uploads/products; false kung hindi atin. */
function delete_stored_image(string $key): bool
{
    if ($key === '' || str_contains($key, "\0")) return false;
    if (preg_match('#^https?://#i', $key)) return false;

    $base = realpath(__DIR__ . '/../../uploads/products');
    if ($base === false) return false;

    $path = realpath(__DIR__ . '/../../' . ltrim($key, '/'));
    if ($path === false || !is_file($path)) return false;
    if (!str_starts_with($path, $base . DIRECTORY_SEPARATOR)) return false;

    return @unlink($path);
}
