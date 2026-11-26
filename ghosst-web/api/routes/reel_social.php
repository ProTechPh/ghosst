<?php
declare(strict_types=1);

function reel_comment_validate(string $text): ?string
{
    $text = trim($text);
    if ($text === '') return 'Write a comment.';
    if (mb_strlen($text, 'UTF-8') > 500) return 'Comment must be 500 characters or less.';
    return null;
}

function reel_social_map(array $row, string $viewerId, array $mediaMap = []): array
{
    $id = (string) ($row['id'] ?? '');
    $images = $mediaMap[$id] ?? [];
    $poster = (string) ($row['poster_url'] ?? '');
    if ($poster === '' && $images !== []) $poster = (string) ($images[0]['url'] ?? '');
    return [
        'id' => $id,
        'caption' => $row['caption'] ?? '',
        'posterUrl' => $poster !== '' ? $poster : null,
        'images' => $images,
        'createdAt' => iso_time($row['created_at'] ?? null),
        'creator' => social_public_user(['id' => $row['user_id'] ?? ''] + $row),
        'likeCount' => (int) ($row['like_count'] ?? 0),
        'commentCount' => (int) ($row['comment_count'] ?? 0),
        'isLiked' => ($row['is_liked'] ?? 0) == 1,
        'isFollowing' => ($row['is_following'] ?? 0) == 1,
        'isMine' => (string) ($row['user_id'] ?? '') === $viewerId,
    ];
}

function reels_feed(array $ctx): array
{
    if (!reels_enabled()) throw new ApiError(503, 'reels_not_configured', 'Reels are not configured.');
    $page = social_pagination($ctx['query'], 10);
    $viewerId = (string) $ctx['user']['id'];
    $feed = ($ctx['query']['feed'] ?? 'for-you') === 'following' ? 'following' : 'for-you';
    $following = $feed === 'following'
        ? 'AND EXISTS (SELECT 1 FROM app_follows f WHERE f.follower_id = ? AND f.creator_id = r.user_id)'
        : '';
    $params = [$viewerId, $viewerId];
    if ($feed === 'following') $params[] = $viewerId;
    $limit = (int) $page['limit'];
    $offset = (int) $page['offset'];
    $rows = all_rows(
        "SELECT r.id, r.user_id, r.caption, r.poster_url, r.created_at,
                u.username, u.display_name, " . social_avatar_select() . ", u.is_admin, u.is_moderator,
                (SELECT COUNT(*) FROM app_reel_likes l WHERE l.reel_id = r.id) AS like_count,
                (SELECT COUNT(*) FROM app_reel_comments c WHERE c.reel_id = r.id AND c.status = 'visible') AS comment_count,
                EXISTS(SELECT 1 FROM app_reel_likes l WHERE l.reel_id = r.id AND l.user_id = ?) AS is_liked,
                EXISTS(SELECT 1 FROM app_follows f WHERE f.follower_id = ? AND f.creator_id = r.user_id) AS is_following
           FROM app_reels r
           JOIN " . T_USERS . " u ON u.id = r.user_id
          WHERE r.status = 'visible'
            AND EXISTS (SELECT 1 FROM app_reel_media m WHERE m.reel_id = r.id AND m.status = 'visible')
            AND u.deleted_at IS NULL AND u.is_banned = 0 $following
          ORDER BY r.created_at DESC, r.id DESC
          LIMIT $limit OFFSET $offset",
        $params
    );
    $mediaMap = reel_visible_media_map(array_column($rows, 'id'));
    return [
        'ok' => true,
        'reels' => array_map(fn ($row) => reel_social_map($row, $viewerId, $mediaMap), $rows),
        'nextOffset' => $page['offset'] + count($rows),
    ];
}

function reels_show(array $ctx): array
{
    $id = (string) ($ctx['params']['id'] ?? '');
    $viewerId = (string) $ctx['user']['id'];
    $row = one(
        "SELECT r.id, r.user_id, r.caption, r.poster_url, r.created_at,
                u.username, u.display_name, " . social_avatar_select() . ", u.is_admin, u.is_moderator,
                (SELECT COUNT(*) FROM app_reel_likes l WHERE l.reel_id = r.id) AS like_count,
                (SELECT COUNT(*) FROM app_reel_comments c WHERE c.reel_id = r.id AND c.status = 'visible') AS comment_count,
                EXISTS(SELECT 1 FROM app_reel_likes l WHERE l.reel_id = r.id AND l.user_id = ?) AS is_liked,
                EXISTS(SELECT 1 FROM app_follows f WHERE f.follower_id = ? AND f.creator_id = r.user_id) AS is_following
           FROM app_reels r JOIN " . T_USERS . " u ON u.id = r.user_id
          WHERE r.id = ? AND r.status = 'visible'
            AND EXISTS (SELECT 1 FROM app_reel_media m WHERE m.reel_id = r.id AND m.status = 'visible')
            AND u.deleted_at IS NULL AND u.is_banned = 0",
        [$viewerId, $viewerId, $id]
    );
    if (!$row) throw new ApiError(404, 'reel_not_found', 'Reel not found.');
    $mediaMap = reel_visible_media_map([$id]);
    return ['ok' => true, 'reel' => reel_social_map($row, $viewerId, $mediaMap)];
}

function reels_like(array $ctx): array
{
    $id = (string) ($ctx['params']['id'] ?? '');
    $uid = (string) $ctx['user']['id'];
    social_require_visible_reel($id);
    run_sql('INSERT IGNORE INTO app_reel_likes (reel_id, user_id, created_at) VALUES (?, ?, ?)', [$id, $uid, now_utc()]);
    return ['ok' => true, 'isLiked' => true, 'likeCount' => (int) scalar('SELECT COUNT(*) FROM app_reel_likes WHERE reel_id = ?', [$id])];
}

function reels_unlike(array $ctx): array
{
    $id = (string) ($ctx['params']['id'] ?? '');
    $uid = (string) $ctx['user']['id'];
    run_sql('DELETE FROM app_reel_likes WHERE reel_id = ? AND user_id = ?', [$id, $uid]);
    return ['ok' => true, 'isLiked' => false, 'likeCount' => (int) scalar('SELECT COUNT(*) FROM app_reel_likes WHERE reel_id = ?', [$id])];
}

function reels_comments_list(array $ctx): array
{
    $id = (string) ($ctx['params']['id'] ?? '');
    social_require_visible_reel($id);
    $page = social_pagination($ctx['query'], 20);
    $limit = (int) $page['limit'];
    $offset = (int) $page['offset'];
    $rows = all_rows(
        "SELECT c.id, c.text, c.created_at, u.id AS user_id, u.username, u.display_name,
                " . social_avatar_select() . ", u.is_admin, u.is_moderator
           FROM app_reel_comments c JOIN " . T_USERS . " u ON u.id = c.user_id
          WHERE c.reel_id = ? AND c.status = 'visible' AND u.deleted_at IS NULL AND u.is_banned = 0
          ORDER BY c.created_at ASC, c.id ASC LIMIT $limit OFFSET $offset",
        [$id]
    );
    return [
        'ok' => true,
        'comments' => array_map(fn ($row) => [
            'id' => $row['id'],
            'text' => $row['text'],
            'createdAt' => iso_time($row['created_at']),
            // Query aliases the user id as `user_id`; social_public_user reads `id`.
            'user' => social_public_user(['id' => $row['user_id'] ?? ''] + $row),
        ], $rows),
        'nextOffset' => $page['offset'] + count($rows),
    ];
}

function reels_comments_create(array $ctx): array
{
    $body = read_json();
    $text = trim((string) ($body['text'] ?? ''));
    $invalid = reel_comment_validate($text);
    if ($invalid !== null) throw new ApiError(400, 'invalid_comment', $invalid);
    $id = (string) ($ctx['params']['id'] ?? '');
    $uid = (string) $ctx['user']['id'];
    $pdo = db();
    $pdo->beginTransaction();
    try {
        one('SELECT id FROM ' . T_USERS . ' WHERE id = ? AND deleted_at IS NULL AND is_banned = 0 FOR UPDATE', [$uid]);
        if (!one('SELECT id FROM app_reels r WHERE ' . reel_visible_where('r') . ' AND id = ?', [$id])) {
            throw new ApiError(404, 'reel_not_found', 'Reel not found.');
        }
        $count = (int) scalar("SELECT COUNT(*) FROM app_reel_comments WHERE user_id = ? AND created_at >= ?", [$uid, gmdate('Y-m-d H:i:s', time() - 3600)]);
        if ($count >= 30) throw new ApiError(429, 'rate_limited', 'You can submit up to 30 comments per hour.');
        $commentId = uuid4();
        run_sql("INSERT INTO app_reel_comments (id, reel_id, user_id, text, status, created_at) VALUES (?, ?, ?, ?, 'visible', ?)", [$commentId, $id, $uid, $text, now_utc()]);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        throw $e;
    }
    return ['ok' => true, 'commentId' => $commentId];
}

function reels_comments_delete(array $ctx): array
{
    $commentId = (string) ($ctx['params']['commentId'] ?? '');
    $uid = (string) $ctx['user']['id'];
    $row = one('SELECT user_id FROM app_reel_comments WHERE id = ?', [$commentId]);
    if (!$row) throw new ApiError(404, 'comment_not_found', 'Comment not found.');
    $moderator = !empty($ctx['user']['isAdmin']) || !empty($ctx['user']['isModerator']);
    if ((string) $row['user_id'] !== $uid && !$moderator) throw new ApiError(403, 'forbidden', 'You cannot delete this comment.');
    run_sql("UPDATE app_reel_comments SET status = 'deleted' WHERE id = ?", [$commentId]);
    return ['ok' => true];
}
