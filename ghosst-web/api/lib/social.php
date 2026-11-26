<?php
declare(strict_types=1);

/** Safe public identity shared by search, profiles, follows, and reels. */
function social_public_user(array $row, array $viewer = []): array
{
    $id = (string) ($row['id'] ?? '');
    $username = trim((string) ($row['username'] ?? ''));
    $name = trim((string) ($row['display_name'] ?? ''));
    if ($name === '') $name = $username !== '' ? $username : 'Member #' . $id;
    $avatar = trim((string) ($row['avatar_url'] ?? ''));
    static $hasBio = null;
    static $hasCover = null;
    if ($hasBio === null) $hasBio = social_column_exists(T_USERS, 'bio');
    if ($hasCover === null) $hasCover = social_column_exists(T_USERS, 'cover_url');
    $bio = $hasBio ? trim((string) ($row['bio'] ?? '')) : '';
    $cover = $hasCover ? trim((string) ($row['cover_url'] ?? '')) : '';
    if ($cover !== '' && !preg_match('#^https?://#i', $cover)) {
        $cover = (defined('PUBLIC_CDN') && PUBLIC_CDN !== '')
            ? rtrim(PUBLIC_CDN, '/') . '/' . ltrim($cover, '/')
            : $cover;
    }

    return [
        'id' => $id,
        'displayName' => $name,
        'username' => $username,
        'avatarUrl' => $avatar !== '' ? $avatar : null,
        'bio' => $bio,
        'coverUrl' => $cover !== '' ? $cover : null,
        'isAdmin' => ($row['is_admin'] ?? false) == true,
        'isModerator' => ($row['is_moderator'] ?? false) == true,
    ];
}

function reel_visible_where(string $alias = 'r'): string
{
    return "$alias.status = 'visible' AND EXISTS (
        SELECT 1 FROM app_reel_media visible_media
         WHERE visible_media.reel_id = $alias.id AND visible_media.status = 'visible'
    ) AND EXISTS (
        SELECT 1 FROM " . T_USERS . " visible_user
         WHERE visible_user.id = $alias.user_id
           AND visible_user.deleted_at IS NULL AND visible_user.is_banned = 0
    )";
}

function reel_visible_media_map(array $reelIds): array
{
    $ids = array_values(array_filter(array_map('strval', $reelIds), fn ($id) => $id !== ''));
    if ($ids === []) return [];
    $marks = implode(',', array_fill(0, count($ids), '?'));
    $rows = all_rows(
        "SELECT reel_id, position, image_url, width, height
           FROM app_reel_media
          WHERE reel_id IN ($marks) AND status = 'visible'
          ORDER BY reel_id ASC, position ASC",
        $ids
    );
    $map = [];
    foreach ($rows as $row) {
        $rid = (string) $row['reel_id'];
        $map[$rid] ??= [];
        $map[$rid][] = [
            'position' => (int) $row['position'],
            'url' => (string) ($row['image_url'] ?? ''),
            'width' => isset($row['width']) ? (int) $row['width'] : null,
            'height' => isset($row['height']) ? (int) $row['height'] : null,
        ];
    }
    return $map;
}

function social_require_visible_reel(string $id): void
{
    if (!one('SELECT id FROM app_reels r WHERE ' . reel_visible_where('r') . ' AND id = ?', [$id])) {
        throw new ApiError(404, 'reel_not_found', 'Reel not found');
    }
}

function social_google_photo_url(?string $url): ?string
{
    if ($url === null) return null;
    $url = trim($url);
    if ($url === '' || strlen($url) > 1000 || !filter_var($url, FILTER_VALIDATE_URL)) return null;
    $parts = parse_url($url);
    if (!is_array($parts)
        || strtolower($parts['scheme'] ?? '') !== 'https'
        || isset($parts['user'])
        || isset($parts['pass'])
        || !preg_match('/(^|\.)googleusercontent\.com$/i', $parts['host'] ?? '')) {
        return null;
    }
    return $url;
}

function social_positive_id(string $id): int
{
    $value = filter_var(trim($id), FILTER_VALIDATE_INT, ['options' => ['min_range' => 1]]);
    if ($value === false) throw new ApiError(400, 'invalid_user', 'User id must be a positive integer');
    return $value;
}

function social_pagination(array $query, int $default = 20): array
{
    $limitRaw = $query['limit'] ?? $default;
    $offsetRaw = $query['offset'] ?? 0;
    if (!is_scalar($limitRaw) || !ctype_digit((string) $limitRaw)) {
        throw new ApiError(400, 'invalid_pagination', 'limit must be an integer');
    }
    if (!is_scalar($offsetRaw) || !ctype_digit((string) $offsetRaw)) {
        throw new ApiError(400, 'invalid_pagination', 'offset must be a non-negative integer');
    }
    return [
        'limit' => max(1, min(50, (int) $limitRaw)),
        'offset' => (int) $offsetRaw,
    ];
}

function social_column_exists(string $table, string $column): bool
{
    if (!preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $table)
        || !preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $column)) {
        return false;
    }
    return one('SHOW COLUMNS FROM ' . $table . " LIKE '" . $column . "'") !== null;
}

function social_avatar_select(): string
{
    static $column = null;
    if ($column === null) {
        $column = social_column_exists(T_USERS, 'avatar_url') ? 'avatar_url' : 'NULL AS avatar_url';
    }
    return $column;
}

function social_user_is_visible(array $row): bool
{
    return ($row['deleted_at'] ?? null) === null && (int) ($row['is_banned'] ?? 0) !== 1;
}

function social_require_target_user(string $id): array
{
    $row = social_user_by_id($id);
    if (!$row) throw new ApiError(404, 'user_not_found', 'User not found');
    return $row;
}

function social_follower_count(string $userId): int
{
    return (int) (scalar(
        'SELECT COUNT(*) FROM app_follows f JOIN ' . T_USERS . ' u ON u.id = f.follower_id
          WHERE f.creator_id = ? AND u.deleted_at IS NULL AND u.is_banned = 0',
        [$userId]
    ) ?? 0);
}

function social_following_count(string $userId): int
{
    return (int) (scalar(
        'SELECT COUNT(*) FROM app_follows f JOIN ' . T_USERS . ' u ON u.id = f.creator_id
          WHERE f.follower_id = ? AND u.deleted_at IS NULL AND u.is_banned = 0',
        [$userId]
    ) ?? 0);
}

function social_profile_counts(string $userId): array
{
    return [
        'followerCount' => social_follower_count($userId),
        'followingCount' => social_following_count($userId),
        'reelCount' => (int) (scalar(
            "SELECT COUNT(*) FROM app_reels r
              WHERE r.user_id = ? AND r.status = 'visible'
                AND EXISTS (SELECT 1 FROM app_reel_media m WHERE m.reel_id = r.id AND m.status = 'visible')",
            [$userId]
        ) ?? 0),
    ];
}

function social_profile_user(array $row, string $viewerId, array $counts = []): array
{
    $id = (string) $row['id'];
    return social_public_user($row) + [
        'createdAt' => iso_time($row['created_at'] ?? null),
        'followerCount' => (int) ($counts['followerCount'] ?? 0),
        'followingCount' => (int) ($counts['followingCount'] ?? 0),
        'reelCount' => (int) ($counts['reelCount'] ?? 0),
        'isFollowing' => $viewerId !== $id && scalar(
            'SELECT 1 FROM app_follows WHERE follower_id = ? AND creator_id = ?',
            [$viewerId, $id]
        ) !== null,
        'isSelf' => $viewerId === $id,
    ];
}

function social_user_by_id(string $id): ?array
{
    $userId = social_positive_id($id);
    $row = one(
        'SELECT id, username, display_name, ' . social_avatar_select() . ',
                created_at, is_admin, is_moderator, deleted_at, is_banned
           FROM ' . T_USERS . ' WHERE id = ? LIMIT 1',
        [$userId]
    );
    if (!$row || !social_user_is_visible($row)) return null;
    return $row;
}

function social_users_by_ids(array $ids): array
{
    $ids = array_values(array_unique(array_map('intval', $ids)));
    if ($ids === []) return [];
    $placeholders = implode(',', array_fill(0, count($ids), '?'));
    return all_rows(
        'SELECT id, username, display_name, ' . social_avatar_select() . ',
                is_admin, is_moderator
           FROM ' . T_USERS . '
          WHERE id IN (' . $placeholders . ') AND deleted_at IS NULL AND is_banned = 0',
        $ids
    );
}

function social_feedback_is_public(array $row): bool
{
    return ($row['source'] ?? 'website') === 'website' && ($row['status'] ?? '') === 'visible';
}

function social_report_validate(array $body): array
{
    $targetType = trim((string) ($body['targetType'] ?? ''));
    $targetId = trim((string) ($body['targetId'] ?? ''));
    $reason = trim((string) ($body['reason'] ?? ''));
    $details = trim((string) ($body['details'] ?? ''));
    $snapshot = null;
    $threadId = trim((string) ($body['threadId'] ?? ''));
    if ($targetType === 'message') {
        $snapshotRaw = $body['snapshot'] ?? null;
        $snapshot = is_string($snapshotRaw) ? trim($snapshotRaw) : null;
    }

    if (!in_array($targetType, ['reel', 'comment', 'user', 'message'], true)) {
        throw new ApiError(400, 'invalid_report', 'Unsupported report target');
    }
    if ($targetId === '' || mb_strlen($targetId, 'UTF-8') > 100) {
        throw new ApiError(400, 'invalid_report', 'targetId must be 1-100 characters');
    }
    if (!in_array($reason, ['spam', 'harassment', 'hate_speech', 'sexual_content', 'violence', 'illegal_content', 'other'], true)) {
        throw new ApiError(400, 'invalid_report', 'Unsupported report reason');
    }
    if (mb_strlen($details, 'UTF-8') > 500) {
        throw new ApiError(400, 'invalid_report', 'details must be at most 500 characters');
    }
    if ($targetType === 'message') {
        if ($snapshot === null || $snapshot === '') {
            throw new ApiError(400, 'invalid_report', 'A message report requires a text snapshot');
        }
        if (!preg_match('/^[A-Za-z0-9_-]+__[A-Za-z0-9_-]+$/', $threadId)) {
            throw new ApiError(400, 'invalid_report', 'A message report requires a valid threadId');
        }
    }
    if ($snapshot !== null && (mb_strlen($snapshot, 'UTF-8') < 1 || mb_strlen($snapshot, 'UTF-8') > 500)) {
        throw new ApiError(400, 'invalid_report', 'snapshot must be 1-500 characters');
    }
    if ($targetType === 'reel') {
        $row = one('SELECT caption FROM app_reels r WHERE id = ? AND ' . reel_visible_where('r'), [$targetId]);
        if (!$row) throw new ApiError(404, 'reel_not_found', 'Reel not found');
        $snapshot = mb_substr((string) $row['caption'], 0, 500, 'UTF-8');
    }
    if ($targetType === 'comment') {
        $row = one('SELECT c.text FROM app_reel_comments c JOIN app_reels r ON r.id = c.reel_id WHERE c.id = ? AND c.status = \'visible\' AND ' . reel_visible_where(), [$targetId]);
        if (!$row) throw new ApiError(404, 'comment_not_found', 'Comment not found');
        $snapshot = mb_substr((string) $row['text'], 0, 500, 'UTF-8');
    }

    return compact('targetType', 'targetId', 'reason', 'details', 'snapshot', 'threadId');
}
