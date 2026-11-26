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

function cover_key_of(string $value): string
{
    if ($value === '') return '';
    if (preg_match('#(uploads/covers/[^?\s]+)#', $value, $match)) return $match[1];
    return '';
}

/** Tanggalin lang ang file sa loob ng isang uploads folder; false kung hindi atin. */
function delete_uploaded_file(string $key, string $folder): bool
{
    if ($key === '' || str_contains($key, "\0")) return false;
    if (preg_match('#^https?://#i', $key)) {
        $key = (string) (parse_url($key, PHP_URL_PATH) ?? '');
    }
    $key = ltrim($key, '/');
    if (!str_starts_with($key, $folder . '/')) return false;

    $base = realpath(__DIR__ . '/../../' . $folder);
    if ($base === false) return false;

    $path = realpath(__DIR__ . '/../../' . $key);
    if ($path === false || !is_file($path)) return false;
    if (!str_starts_with($path, $base . DIRECTORY_SEPARATOR)) return false;

    return @unlink($path);
}

function delete_stored_image(string $key): bool
{
    return delete_uploaded_file($key, 'uploads/products');
}

function delete_cover_image(string $key): bool
{
    return delete_uploaded_file($key, 'uploads/covers');
}
