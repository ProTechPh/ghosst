<?php
declare(strict_types=1);

/** Isang announcement row papuntang JSON na binabasa ng app. */
function announcement_json(array $row): array
{
    return [
        'id'        => (string) ($row['id'] ?? ''),
        'title'     => (string) ($row['title'] ?? ''),
        'body'      => (string) ($row['body'] ?? ''),
        'createdAt' => (string) ($row['created_at'] ?? ''),
    ];
}

/** Pinakabagong announcement na buhay pa; null kapag wala. */
function announcements_latest(array $ctx): array
{
    $row = one(
        'SELECT id, title, body, created_at FROM ' . T_ANNOUNCEMENTS
        . ' WHERE active = 1 AND (expires_at IS NULL OR expires_at > UTC_TIMESTAMP())'
        . ' ORDER BY created_at DESC LIMIT 1'
    );

    return ['announcement' => $row ? announcement_json($row) : null];
}

/** Admin post: save it (7-day banner), then broadcast it. */
function announcements_create(array $ctx): array
{
    require_admin($ctx);
    $body = read_json();

    $title = mb_substr(trim((string) ($body['title'] ?? '')), 0, 120, 'UTF-8');
    $text = mb_substr(trim((string) ($body['body'] ?? '')), 0, 2000, 'UTF-8');
    if ($title === '' || $text === '') {
        throw new ApiError(400, 'invalid_announcement', 'Title and body are required');
    }

    $id = uuid4();
    $now = now_utc();
    $expires = gmdate('Y-m-d H:i:s', time() + 7 * 86400);

    run_sql(
        'INSERT INTO ' . T_ANNOUNCEMENTS . ' (id, title, body, active, expires_at, created_at)'
        . ' VALUES (?, ?, ?, 1, ?, ?)',
        [$id, $title, $text, $expires, $now]
    );

    $row = one(
        'SELECT id, title, body, created_at FROM ' . T_ANNOUNCEMENTS . ' WHERE id = ?',
        [$id]
    );

    // Push last: the row is already saved, so a dead push service costs nothing.
    $pushed = push_send($title, $text);

    return [
        'ok'           => true,
        'announcement' => announcement_json($row ?? []),
        'pushed'       => $pushed,
    ];
}
