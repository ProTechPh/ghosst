<?php
declare(strict_types=1);

require_once __DIR__ . '/../lib/uploads.php';

function users_search(array $ctx): array
{
    $q = trim((string) ($ctx['query']['q'] ?? ''));
    if (mb_strlen($q, 'UTF-8') < 2) return ['ok' => true, 'users' => [], 'nextOffset' => 0];

    $page = social_pagination($ctx['query']);
    $like = '%' . $q . '%';
    $rows = all_rows(
        'SELECT id, username, display_name, ' . social_avatar_select() . ',
                ' . social_profile_select() . ',
                is_admin, is_moderator, deleted_at, is_banned
           FROM ' . T_USERS . '
          WHERE deleted_at IS NULL AND is_banned = 0
            AND (display_name LIKE ? OR username LIKE ?)
          ORDER BY display_name ASC, id ASC
          LIMIT ? OFFSET ?',
        [$like, $like, $page['limit'], $page['offset']]
    );

    return [
        'ok' => true,
        'users' => array_map('social_public_user', $rows),
        'nextOffset' => $page['offset'] + count($rows),
    ];
}

function users_summaries(array $ctx): array
{
    $body = read_json();
    $ids = $body['ids'] ?? null;
    if (!is_array($ids) || $ids === [] || count($ids) > 50) {
        throw new ApiError(400, 'invalid_users', 'ids must contain 1-50 user ids');
    }
    $clean = [];
    foreach ($ids as $id) {
        $clean[] = (string) social_positive_id((string) $id);
    }
    return [
        'ok' => true,
        'users' => array_map('social_public_user', social_users_by_ids($clean)),
    ];
}

function users_show(array $ctx): array
{
    $row = social_user_by_id((string) ($ctx['params']['id'] ?? ''));
    if (!$row) throw new ApiError(404, 'user_not_found', 'User not found');
    $id = (string) $row['id'];
    $viewerId = (string) $ctx['user']['id'];
    return [
        'ok' => true,
        'user' => social_profile_user($row, $viewerId, social_profile_counts($id)),
    ];
}

function users_reels(array $ctx): array
{
    $row = social_user_by_id((string) ($ctx['params']['id'] ?? ''));
    if (!$row) throw new ApiError(404, 'user_not_found', 'User not found');
    $page = social_pagination($ctx['query']);
    $limit = (int) $page['limit'];
    $offset = (int) $page['offset'];
    $rows = all_rows(
        "SELECT r.id, r.caption, r.poster_url, r.created_at
           FROM app_reels r
          WHERE r.user_id = ? AND r.status = 'visible'
            AND EXISTS (SELECT 1 FROM app_reel_media m WHERE m.reel_id = r.id AND m.status = 'visible')
          ORDER BY r.created_at DESC, r.id DESC
          LIMIT $limit OFFSET $offset",
        [$row['id']]
    );
    $mediaMap = reel_visible_media_map(array_column($rows, 'id'));
    return [
        'ok' => true,
        'user' => social_public_user($row),
        'reels' => array_map(function ($reel) use ($row, $mediaMap) {
            $id = (string) ($reel['id'] ?? '');
            $images = $mediaMap[$id] ?? [];
            $poster = (string) ($reel['poster_url'] ?? '');
            if ($poster === '' && $images !== []) $poster = (string) ($images[0]['url'] ?? '');
            return [
                'id' => $id,
                'caption' => (string) ($reel['caption'] ?? ''),
                'posterUrl' => $poster !== '' ? $poster : null,
                'images' => $images,
                'createdAt' => iso_time($reel['created_at'] ?? null),
                'creator' => social_public_user($row),
            ];
        }, $rows),
        'nextOffset' => $page['offset'] + count($rows),
    ];
}

/** Plain-text bio at/o FTP cover URL sa sariling profile. */
function users_update_bio(array $ctx): array
{
    $uid = (string) $ctx['user']['id'];
    $body = read_json();
    $bio = array_key_exists('bio', $body) ? trim((string) $body['bio']) : null;
    $cover = array_key_exists('cover', $body) ? trim((string) $body['cover']) : null;
    if ($bio === null && $cover === null) {
        throw new ApiError(400, 'nothing_to_update', 'Send a bio or cover.');
    }
    if ($bio !== null) {
        $invalid = profile_bio_validate($bio);
        if ($invalid !== null) throw new ApiError(400, 'invalid_bio', $invalid);
        if (!social_column_exists(T_USERS, 'bio')) {
            throw new ApiError(503, 'server_schema', 'Bio is not set up yet.');
        }
    }
    if ($cover !== null) {
        if ($cover !== '' && !preg_match('#^(https?://|uploads/covers/)#i', $cover)) {
            throw new ApiError(400, 'invalid_cover', 'Invalid cover URL.');
        }
        if (!social_column_exists(T_USERS, 'cover_url')) {
            throw new ApiError(503, 'server_schema', 'Cover is not set up yet.');
        }
    }

    $sets = [];
    $params = [];
    if ($bio !== null) { $sets[] = 'bio = ?'; $params[] = $bio; }
    if ($cover !== null) {
        $sets[] = 'cover_url = ?';
        $params[] = $cover === '' ? null : cover_image_url($cover);
    }
    $params[] = $uid;
    run_sql('UPDATE ' . T_USERS . ' SET ' . implode(', ', $sets) . ' WHERE id = ?', $params);

    $result = ['ok' => true];
    if ($bio !== null) $result['bio'] = $bio;
    if ($cover !== null) $result['coverUrl'] = cover_image_url($cover);
    return $result;
}
