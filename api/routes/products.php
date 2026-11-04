<?php
declare(strict_types=1);

const SELECT_PRODUCTS = 'SELECT p.id, p.name, p.cost, p.active, p.description, p.youtube_url,
                                 p.type, p.version, p.file_size
                            FROM ' . T_PRODUCTS . ' p';

function to_product(array $row, array $images, array $durations): array
{
    return [
        'id'             => $row['id'],
        'name'           => $row['name'],
        'cost'           => (int) $row['cost'],
        'active'         => (int) $row['active'] === 1,
        // Buong URL (Cloudinary/MediaFire) ay dumadaan lang; key ay dinadagdagan ng CDN.
        'imageUrls'      => array_map(
            fn ($k) => preg_match('#^https?://#i', $k) ? $k : (PUBLIC_CDN !== '' ? PUBLIC_CDN . '/' . $k : $k),
            $images
        ),
        'youtubeUrl'     => $row['youtube_url'],
        'type'           => $row['type'],
        'version'        => $row['version'],
        'fileSize'       => $row['file_size'],
        'durations'      => $durations,
        // Para lang sa shape; nasa admin endpoint ang totoong bilang.
        'availableCount' => 0,
    ];
}

/** @param array<int,array> $rows */
function attach_relations(array $rows): array
{
    if (!$rows) return [];

    $ids = array_column($rows, 'id');
    $in = implode(',', array_fill(0, count($ids), '?'));

    $images = all_rows(
        'SELECT product_id, object_key FROM ' . T_IMAGES . ' WHERE product_id IN (' . $in . ') ORDER BY position',
        $ids
    );
    $durations = all_rows(
        'SELECT product_id, label, cost FROM ' . T_DURATIONS . ' WHERE product_id IN (' . $in . ') ORDER BY cost',
        $ids
    );

    $byImage = [];
    foreach ($images as $i) $byImage[$i['product_id']][] = $i['object_key'];

    $byDuration = [];
    foreach ($durations as $d) {
        $byDuration[$d['product_id']][] = ['label' => $d['label'], 'cost' => (int) $d['cost']];
    }

    return array_map(
        fn ($row) => to_product($row, $byImage[$row['id']] ?? [], $byDuration[$row['id']] ?? []),
        $rows
    );
}

function products_list(array $ctx): array
{
    $includeInactive = ($ctx['query']['all'] ?? '') === '1' && !empty($ctx['user']['isAdmin']);
    $sql = SELECT_PRODUCTS . ($includeInactive ? '' : ' WHERE p.active = 1') . ' ORDER BY p.name';

    return ['ok' => true, 'products' => attach_relations(all_rows($sql))];
}

function products_get(array $ctx): array
{
    $isAdmin = !empty($ctx['user']['isAdmin']);
    $row = one(
        SELECT_PRODUCTS . ' WHERE p.id = ?' . ($isAdmin ? '' : ' AND p.active = 1'),
        [$ctx['params']['id']]
    );
    if (!$row) throw new ApiError(404, 'product_not_found', 'Product not found');

    [$product] = attach_relations([$row]);

    // Ang naka-store na download link ay para sa admin lang.
    $fileUrl = '';
    if ($isAdmin) {
        $fileUrl = (string) (scalar(
            'SELECT object_key FROM ' . T_FILES . ' WHERE product_id = ?',
            [$row['id']]
        ) ?? '');
    }

    return ['ok' => true, 'product' => $product + ['fileUrl' => $fileUrl]];
}

function products_create(array $ctx): array
{
    require_admin($ctx);
    $body = read_json();

    $name = trim((string) ($body['name'] ?? ''));
    if ($name === '') throw new ApiError(400, 'invalid_product', 'Name is required');

    $type = (string) ($body['type'] ?? 'key');
    if (!in_array($type, ['key', 'apk', 'file'], true)) {
        throw new ApiError(400, 'invalid_product', 'type must be key, apk or file');
    }

    $id = uuid4();
    $now = now_utc();
    $active = ($body['active'] ?? true) === false ? 0 : 1;

    run_sql(
        'INSERT INTO ' . T_PRODUCTS . ' (id, name, cost, active, description, youtube_url, type, version, file_size, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
            $id,
            $name,
            max(0, (int) floor((float) ($body['cost'] ?? 50))),
            $active,
            (string) ($body['description'] ?? ''),
            (string) ($body['youtubeUrl'] ?? ''),
            $type,
            (string) ($body['version'] ?? ''),
            (string) ($body['fileSize'] ?? ''),
            $now,
            $now,
        ]
    );

    apply_relations($id, $body);

    // Hidden products were not announced; only what the store shows goes out.
    if ($active === 1) push_send('Bagong product: ' . $name, 'Bagong listing sa store.');

    return products_get(['params' => ['id' => $id], 'user' => $ctx['user'], 'query' => []]);
}

function products_update(array $ctx): array
{
    require_admin($ctx);
    $body = read_json();
    $id = $ctx['params']['id'];

    $exists = one('SELECT id FROM ' . T_PRODUCTS . ' WHERE id = ?', [$id]);
    if (!$exists) throw new ApiError(404, 'product_not_found', 'Product not found');

    $before = [];
    if (array_key_exists('imageKeys', $body)) {
        $before = array_column(
            all_rows('SELECT object_key FROM ' . T_IMAGES . ' WHERE product_id = ?', [$id]),
            'object_key'
        );
    }

    run_sql(
        'UPDATE ' . T_PRODUCTS . ' SET
           name = COALESCE(?, name),
           cost = COALESCE(?, cost),
           description = COALESCE(?, description),
           youtube_url = COALESCE(?, youtube_url),
           type = COALESCE(?, type),
           version = COALESCE(?, version),
           file_size = COALESCE(?, file_size),
           active = COALESCE(?, active),
           updated_at = ?
         WHERE id = ?',
        [
            isset($body['name']) ? (string) $body['name'] : null,
            isset($body['cost']) ? max(0, (int) floor((float) $body['cost'])) : null,
            isset($body['description']) ? (string) $body['description'] : null,
            isset($body['youtubeUrl']) ? (string) $body['youtubeUrl'] : null,
            isset($body['type']) ? (string) $body['type'] : null,
            isset($body['version']) ? (string) $body['version'] : null,
            isset($body['fileSize']) ? (string) $body['fileSize'] : null,
            array_key_exists('active', $body) ? ($body['active'] ? 1 : 0) : null,
            now_utc(),
            $id,
        ]
    );

    apply_relations($id, $body);

    if (array_key_exists('imageKeys', $body)) {
        $kept = array_flip($body['imageKeys']);
        discard_images(array_values(array_filter($before, fn ($k) => !isset($kept[$k]))));
    }

    // Ang naka-store na download link ay kasama ng product sa admin form.
    if (array_key_exists('fileUrl', $body)) {
        $link = trim((string) $body['fileUrl']);
        if ($link !== '') {
            $filename = basename((string) parse_url($link, PHP_URL_PATH));
            run_sql(
                'INSERT INTO ' . T_FILES . ' (product_id, object_key, filename, updated_at) VALUES (?, ?, ?, ?)
                 ON DUPLICATE KEY UPDATE object_key = VALUES(object_key), sha256 = NULL, updated_at = VALUES(updated_at)',
                [$id, $link, $filename !== '' ? $filename : 'download', now_utc()]
            );
        } else {
            run_sql('DELETE FROM ' . T_FILES . ' WHERE product_id = ?', [$id]);
        }
    }

    return products_get(['params' => ['id' => $id], 'user' => $ctx['user'], 'query' => []]);
}

function products_remove(array $ctx): array
{
    require_admin($ctx);
    $id = $ctx['params']['id'];

    $images = array_column(
        all_rows('SELECT object_key FROM ' . T_IMAGES . ' WHERE product_id = ?', [$id]),
        'object_key'
    );
    $file = scalar('SELECT object_key FROM ' . T_FILES . ' WHERE product_id = ?', [$id]);

    // Images, durations, files at keys ay CASCADE sa FK.
    run_sql('DELETE FROM ' . T_PRODUCTS . ' WHERE id = ?', [$id]);

    $keys = $images;
    if ($file) $keys[] = $file;

    return ['ok' => true, 'filesDeleted' => discard_images($keys)];
}

/** Best effort: ang dangling object ay storage cost, hindi correctness. */
function discard_images(array $keys): int
{
    $deleted = 0;
    foreach ($keys as $key) {
        if (preg_match('#^https?://#i', $key)) {
            if (destroy_image($key)) $deleted++;
        }
    }
    return $deleted;
}

/** Buong list ang ipinapadala ng admin UI, kaya replace-all ang galawan. */
function apply_relations(string $productId, array $body): void
{
    if (array_key_exists('imageKeys', $body)) {
        run_sql('DELETE FROM ' . T_IMAGES . ' WHERE product_id = ?', [$productId]);
        $now = now_utc();
        foreach (array_values($body['imageKeys']) as $position => $key) {
            run_sql(
                'INSERT INTO ' . T_IMAGES . ' (id, product_id, object_key, position, created_at) VALUES (?, ?, ?, ?, ?)',
                [uuid4(), $productId, (string) $key, $position, $now]
            );
        }
    }

    if (array_key_exists('durations', $body)) {
        run_sql('DELETE FROM ' . T_DURATIONS . ' WHERE product_id = ?', [$productId]);
        foreach ($body['durations'] as $d) {
            $label = (string) ($d['label'] ?? '');
            if ($label === '') continue;
            run_sql(
                'INSERT INTO ' . T_DURATIONS . ' (product_id, label, cost) VALUES (?, ?, ?)
                 ON DUPLICATE KEY UPDATE cost = VALUES(cost)',
                [$productId, $label, max(0, (int) floor((float) ($d['cost'] ?? 0)))]
            );
        }
    }
}
