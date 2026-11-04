<?php
declare(strict_types=1);

const KEYS_PER_STATEMENT = 500;

/** POST /v1/admin/keys — bulk paste, deduped ng UNIQUE(product_id, key_value). */
function keys_add(array $ctx): array
{
    require_admin($ctx);
    $body = read_json();

    $productId = (string) ($body['productId'] ?? '');
    if ($productId === '') throw new ApiError(400, 'invalid_product', 'productId is required');

    $duration = mb_substr(trim((string) ($body['duration'] ?? '')), 0, 50, 'UTF-8');

    $values = [];
    foreach ((array) ($body['keys'] ?? []) as $k) {
        $k = trim((string) $k);
        if ($k !== '') $values[$k] = true;
    }
    $values = array_keys($values);

    if (!$values) throw new ApiError(400, 'no_keys', 'No keys to add');
    if (count($values) > 20_000) throw new ApiError(413, 'too_many_keys', 'Max 20,000 keys per request');

    $product = one('SELECT id, name FROM ' . T_PRODUCTS . ' WHERE id = ?', [$productId]);
    if (!$product) throw new ApiError(404, 'product_not_found', 'Product not found');

    // Restock is per pool: a product can be sold out in one duration only.
    $before = (int) scalar(
        'SELECT COUNT(*) FROM ' . T_KEYS
        . " WHERE product_id = ? AND status = 'available' AND COALESCE(duration, '') = ?",
        [$productId, $duration]
    );

    $added = 0;
    $now = now_utc();

    foreach (array_chunk($values, KEYS_PER_STATEMENT) as $chunk) {
        $tuple = "(?, ?, ?, 'available', ?, ?)";
        $sql = 'INSERT IGNORE INTO ' . T_KEYS . ' (id, product_id, key_value, status, duration, created_at) VALUES '
             . implode(',', array_fill(0, count($chunk), $tuple));

        $params = [];
        foreach ($chunk as $key) {
            array_push($params, uuid4(), $productId, $key, $duration, $now);
        }

        $st = db()->prepare($sql);
        $st->execute($params);
        $added += $st->rowCount();
    }

    // Only a sold-out pool coming back to life is news; top-ups stay silent.
    if ($before === 0 && $added > 0) {
        push_send(
            'Bagong stock: ' . (string) $product['name'],
            $duration !== '' ? $duration : 'Available na ulit'
        );
    }

    return [
        'ok'        => true,
        'submitted' => count($values),
        'added'     => $added,
        'skipped'   => count($values) - $added,
    ];
}

/**
 * GET /v1/admin/keys?productId=&status=available&limit=500
 * GET /v1/admin/keys?productId=&status=available&count=1 -> { total }
 */
function keys_list(array $ctx): array
{
    require_admin($ctx);
    $q = $ctx['query'];

    $productId = (string) ($q['productId'] ?? '');
    $status = (string) ($q['status'] ?? '');
    $limit = min((int) ($q['limit'] ?? 500) ?: 500, 5000);

    $filters = [];
    $params = [];
    if ($productId !== '') {
        $filters[] = 'product_id = ?';
        $params[] = $productId;
    }
    if ($status !== '') {
        $filters[] = 'status = ?';
        $params[] = $status;
    }
    if (($q['count'] ?? '') === '1' && ($q['duration'] ?? '') !== '') {
        $filters[] = 'duration = ?';
        $params[] = (string) $q['duration'];
    }
    $where = $filters ? ' WHERE ' . implode(' AND ', $filters) : '';

    if (($q['count'] ?? '') === '1') {
        return ['ok' => true, 'total' => (int) (scalar('SELECT COUNT(*) FROM ' . T_KEYS . $where, $params) ?? 0)];
    }

    $rows = all_rows(
        'SELECT id, product_id, key_value, status, duration, claimed_by, claimed_at, created_at
           FROM ' . T_KEYS . $where . ' ORDER BY created_at LIMIT ' . $limit,
        $params
    );

    $keys = array_map(fn ($r) => [
        'id'        => $r['id'],
        'productId' => $r['product_id'],
        'key'       => $r['key_value'],
        'status'    => $r['status'],
        'duration'  => $r['duration'],
        'claimedBy' => $r['claimed_by'],
        'claimedAt' => iso_time($r['claimed_at']),
        'createdAt' => iso_time($r['created_at']),
    ], $rows);

    return ['ok' => true, 'keys' => $keys, 'total' => count($keys)];
}

/** DELETE /v1/admin/keys/:id */
function keys_remove(array $ctx): array
{
    require_admin($ctx);
    run_sql('DELETE FROM ' . T_KEYS . ' WHERE id = ?', [$ctx['params']['id']]);
    return ['ok' => true];
}

/** DELETE /v1/admin/products/:id/keys?status=claimed */
function keys_clear_for_product(array $ctx): array
{
    require_admin($ctx);
    $status = (string) ($ctx['query']['status'] ?? '');

    $deleted = $status !== ''
        ? run_sql('DELETE FROM ' . T_KEYS . ' WHERE product_id = ? AND status = ?', [$ctx['params']['id'], $status])
        : run_sql('DELETE FROM ' . T_KEYS . ' WHERE product_id = ?', [$ctx['params']['id']]);

    return ['ok' => true, 'deleted' => $deleted];
}
