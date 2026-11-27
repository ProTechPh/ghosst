<?php
declare(strict_types=1);

require_once __DIR__ . '/../lib/uploads.php';

/** Public rows from feedback.php — same visible/website filter as the site. */
function public_feedback_map(array $row): array
{
    $image = trim((string) ($row['image_path'] ?? ''));
    return [
        'id' => (int) ($row['id'] ?? 0),
        'username' => trim((string) ($row['username'] ?? '')),
        'comment' => trim((string) ($row['comment'] ?? '')),
        'rating' => max(0, min(5, (int) ($row['rating'] ?? 0))),
        'imageUrl' => $image === '' ? null : product_image_url($image),
        'createdAt' => (string) ($row['created_at'] ?? ''),
    ];
}

function feedback_public(array $ctx): array
{
    $rows = all_rows(
        'SELECT f.id, f.comment, f.rating, f.image_path, f.created_at, u.username
           FROM feedbacks f JOIN users u ON u.id = f.user_id
          WHERE f.status = "visible" AND f.source = "website"
          ORDER BY f.created_at DESC LIMIT 50'
    );
    return ['feedbacks' => array_map('public_feedback_map', $rows)];
}

function feedback_rating(mixed $raw): ?int
{
    return is_int($raw) && $raw >= 1 && $raw <= 5 ? $raw : null;
}

function feedback_validate(string $comment, int $rating): ?string
{
    $comment = trim($comment);
    $length = mb_strlen($comment, 'UTF-8');
    if ($length < 10) return 'Comment must be at least 10 characters.';
    if ($length > 1000) return 'Comment must be 1000 characters or less.';
    if (preg_match('/<[a-zA-Z\/!]/', $comment)) return 'HTML tags are not allowed.';
    if ($rating < 1 || $rating > 5) return 'Rating must be 1-5.';
    return null;
}

function feedback_window_start(): string
{
    return gmdate('Y-m-d H:i:s', time() - 86400);
}

function feedback_account_active(array $row): bool
{
    return ($row['deleted_at'] ?? null) === null && (int) ($row['is_banned'] ?? 0) !== 1;
}

function feedback_create(array $ctx): array
{
    $body = read_json();
    $comment = trim((string) ($body['comment'] ?? ''));
    $rating = feedback_rating($body['rating'] ?? null);
    if ($rating === null) throw new ApiError(400, 'invalid_rating', 'Rating must be an integer from 1 to 5.');
    $invalid = feedback_validate($comment, $rating);
    if ($invalid !== null) throw new ApiError(400, 'invalid_feedback', $invalid);

    $idemKey = trim(header_value('idempotency-key'));
    if ($idemKey === '' || strlen($idemKey) > 128) {
        throw new ApiError(400, 'bad_idempotency_key', 'A valid Idempotency-Key header is required.');
    }

    $uid = (string) $ctx['user']['id'];
    $pdo = db();
    $pdo->beginTransaction();
    try {
        $account = one(
            'SELECT id, deleted_at, is_banned FROM ' . T_USERS . ' WHERE id = ? FOR UPDATE',
            [$uid]
        );
        if (!$account || !feedback_account_active($account)) {
            throw new ApiError(401, 'unauthorized', 'Account is not available.');
        }

        $reservation = idem_reserve($uid, $idemKey);
        if ($reservation['state'] === 'replay') {
            $pdo->commit();
            return json_decode($reservation['response'], true) ?: ['ok' => false];
        }
        if ($reservation['state'] === 'in_flight') {
            throw new ApiError(409, 'request_in_progress', 'Same feedback is still being sent.', 2);
        }

        $since = feedback_window_start();
        $count = (int) (scalar(
            "SELECT COUNT(*) FROM feedbacks WHERE user_id = ? AND source = 'app' AND created_at >= ?",
            [$uid, $since]
        ) ?? 0);
        if ($count >= 5) {
            $oldest = to_epoch((string) scalar(
                "SELECT MIN(created_at) FROM feedbacks WHERE user_id = ? AND source = 'app' AND created_at >= ?",
                [$uid, $since]
            ));
            $retryAfter = $oldest === null ? 86400 : max(1, $oldest + 86400 - time());
            throw new ApiError(429, 'rate_limited', 'You can submit up to 5 feedback messages per rolling 24 hours.', $retryAfter);
        }

        run_sql(
            "INSERT INTO feedbacks (user_id, comment, rating, image_path, source, status, created_at)
             VALUES (?, ?, ?, NULL, 'app', 'hidden', ?)",
            [$uid, $comment, $rating, now_utc()]
        );
        $result = ['ok' => true, 'feedbackId' => (string) db()->lastInsertId()];
        idem_complete($uid, $idemKey, json_encode_body($result));
        $pdo->commit();
        return $result;
    } catch (Throwable $e) {
        $pdo->rollBack();
        throw $e;
    }
}

function feedback_mine(array $ctx): array
{
    $page = social_pagination($ctx['query']);
    $uid = (string) $ctx['user']['id'];
    $rows = all_rows(
        "SELECT id, comment, rating, status, created_at FROM feedbacks
          WHERE user_id = ? AND source = 'app'
          ORDER BY created_at DESC, id DESC
          LIMIT ? OFFSET ?",
        [$uid, $page['limit'], $page['offset']]
    );
    return [
        'ok' => true,
        'feedbacks' => array_map(fn ($row) => [
            'id' => (string) $row['id'],
            'comment' => $row['comment'],
            'rating' => (int) $row['rating'],
            'status' => $row['status'],
            'createdAt' => iso_time($row['created_at']),
        ], $rows),
        'nextOffset' => $page['offset'] + count($rows),
    ];
}
