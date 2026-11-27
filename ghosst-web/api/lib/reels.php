<?php
declare(strict_types=1);

function reel_b64url_encode(string $raw): string
{
    return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
}

function reel_b64url_decode(string $value): string
{
    return base64_decode(strtr($value, '-_', '+/'), true) ?: '';
}

function reels_enabled(): bool
{
    return REEL_UPLOAD_SECRET !== '' && REEL_PUBLIC_BASE_URL !== '' && REEL_UPLOAD_URL !== '';
}

function reel_allowed_image(string $mime, string $ext): bool
{
    return in_array([strtolower($mime), strtolower($ext)], [
        ['image/jpeg', 'jpg'],
        ['image/jpeg', 'jpeg'],
        ['image/png', 'png'],
        ['image/webp', 'webp'],
    ], true);
}

function reel_media_ext_for_mime(string $mime): ?string
{
    return match (strtolower($mime)) {
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        default => null,
    };
}

function reel_media_public_url(string $reelId, int $position, string $ext): string
{
    if (!preg_match('/^[A-Za-z0-9-]{1,64}$/', $reelId) || $position < 1 || $position > 5) return '';
    $ext = strtolower($ext);
    if (!in_array($ext, ['jpg', 'jpeg', 'png', 'webp'], true)) return '';
    return rtrim(REEL_PUBLIC_BASE_URL, '/') . '/' . $reelId . '-' . $position . '.' . $ext;
}

function reel_ticket_sign(array $claims, int $ttl = 900): string
{
    $claims['iat'] = time();
    $claims['exp'] = $claims['iat'] + $ttl;
    $claims['jti'] = $claims['jti'] ?? bin2hex(random_bytes(8));
    $head = reel_b64url_encode(json_encode(['alg' => 'HS256', 'typ' => 'JWT']));
    $body = reel_b64url_encode(json_encode($claims));
    $sig = reel_b64url_encode(hash_hmac('sha256', $head . '.' . $body, REEL_UPLOAD_SECRET, true));
    return $head . '.' . $body . '.' . $sig;
}

function reel_ticket_verify(string $token, string $purpose): ?array
{
    if (REEL_UPLOAD_SECRET === '') return null;
    $parts = explode('.', $token);
    if (count($parts) !== 3) return null;
    [$head, $body, $sig] = $parts;
    $expected = reel_b64url_encode(hash_hmac('sha256', $head . '.' . $body, REEL_UPLOAD_SECRET, true));
    if (!hash_equals($expected, $sig)) return null;
    $header = json_decode(reel_b64url_decode($head), true);
    $claims = json_decode(reel_b64url_decode($body), true);
    if (!is_array($header) || !is_array($claims) || ($header['alg'] ?? '') !== 'HS256') return null;
    if (($claims['purpose'] ?? '') !== $purpose || (int) ($claims['exp'] ?? 0) < time()) return null;
    if (!is_string($claims['sub'] ?? null) || !is_string($claims['reelId'] ?? null)
        || !is_string($claims['sha256'] ?? null) || !preg_match('/^[a-f0-9]{64}$/', $claims['sha256'])
        || !is_int($claims['sizeBytes'] ?? null) || $claims['sizeBytes'] < 1
        || !is_string($claims['jti'] ?? null)) {
        return null;
    }
    if ($purpose === 'reel-image-upload') {
        $position = $claims['position'] ?? null;
        $mime = $claims['mimeType'] ?? null;
        $ext = $claims['ext'] ?? null;
        if (!is_int($position) || $position < 1 || $position > 5) return null;
        if (!is_string($mime) || !is_string($ext) || !reel_allowed_image($mime, $ext)) return null;
        if ($claims['sizeBytes'] > 10485760) return null;
        return $claims;
    }
    if ($claims['sizeBytes'] > 52428800) return null;
    return $claims;
}

/** Same-host FTP media: delete files directly, no ticket/network involved. */
function reels_delete_local_files(array $reelIds): int
{
    $root = realpath(__DIR__ . '/../../reels/media');
    if ($root === false) return 0;
    $deleted = 0;
    foreach ($reelIds as $reelId) {
        $id = (string) $reelId;
        if (!preg_match('/^[a-f0-9-]{36}$/i', $id)) continue;
        $names = [$id . '.mp4'];
        foreach (range(1, 5) as $position) {
            foreach (['jpg', 'jpeg', 'png', 'webp'] as $ext) {
                $names[] = $id . '-' . $position . '.' . $ext;
            }
        }
        foreach ($names as $name) {
            $path = $root . DIRECTORY_SEPARATOR . $name;
            if (!is_file($path)) continue;
            $real = realpath($path);
            if ($real === false || dirname($real) !== $root) continue;
            if (@unlink($real)) $deleted++;
        }
    }
    return $deleted;
}

function reels_delete_files(array $reelIds): void
{
    $ids = array_values(array_filter(array_map('strval', $reelIds), fn ($id) => preg_match('/^[a-f0-9-]{36}$/i', $id)));
    if ($ids === []) return;
    reels_delete_local_files($ids);
    if (!reels_enabled()) return;
    try {
        foreach ($ids as $reelId) {
            $token = reel_ticket_sign([
                'sub' => 'admin',
                'reelId' => $reelId,
                'purpose' => 'reel-delete',
                'sha256' => str_repeat('0', 64),
                'sizeBytes' => 1,
            ], 300);
            $ch = curl_init(rtrim(dirname(REEL_UPLOAD_URL), '/') . '/delete.php');
            curl_setopt_array($ch, [
                CURLOPT_POST => true,
                CURLOPT_POSTFIELDS => http_build_query(['manifest' => json_encode([$reelId])]),
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_CONNECTTIMEOUT => 3,
                CURLOPT_TIMEOUT => 5,
                CURLOPT_HTTPHEADER => ['Authorization: Bearer ' . $token],
            ]);
            $response = curl_exec($ch);
            if ($response === false) throw new RuntimeException(curl_error($ch));
            $httpCode = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            if ($httpCode < 200 || $httpCode >= 300) {
                throw new RuntimeException("Media cleanup returned HTTP $httpCode");
            }
        }
    } catch (Throwable $e) {
        error_log('Reel media cleanup failed: ' . $e->getMessage());
    }
}

function reel_public_url(string $reelId): string
{
    return rtrim(REEL_PUBLIC_BASE_URL, '/') . '/' . $reelId . '.mp4';
}
