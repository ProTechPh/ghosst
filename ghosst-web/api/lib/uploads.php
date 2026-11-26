<?php
declare(strict_types=1);

/** Relative image key → absolute URL para sa preview agad pagkatapos ng upload. */
function product_image_url(string $path): string
{
    if (preg_match('#^https?://#i', $path)) return $path;
    if (!defined('PUBLIC_CDN') || PUBLIC_CDN === '') return $path;
    return rtrim(PUBLIC_CDN, '/') . '/' . ltrim($path, '/');
}

function cover_image_url(string $path): string
{
    return product_image_url($path);
}

/** Plain-text bio lang; walang HTML at may limit. */
function profile_bio_validate(string $bio): ?string
{
    $bio = trim($bio);
    if (mb_strlen($bio, 'UTF-8') > 300) return 'Bio must be 300 characters or less.';
    if (preg_match('/<[a-zA-Z\/!]/', $bio)) return 'HTML tags are not allowed.';
    return null;
}

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
