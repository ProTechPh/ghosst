<?php
declare(strict_types=1);

function account_me(array $ctx): array
{
    $row = one(
        'SELECT id, email, display_name, coins, referral_code, is_admin, is_moderator, chat_muted, muted_until, created_at FROM ' . T_USERS . ' WHERE id = ?',
        [$ctx['user']['id']]
    );
    if (!$row) throw new ApiError(401, 'unauthorized', 'Account not found');

    return [
        'ok'   => true,
        'user' => [
            'id'          => (string) $row['id'],
            'email'       => $row['email'],
            'displayName' => $row['display_name'],
            'coins'       => (int) $row['coins'],
            'referralCode' => (string) $row['referral_code'],
            'isAdmin'     => (int) $row['is_admin'] === 1,
            'isModerator' => (int) ($row['is_moderator'] ?? 0) === 1,
            'chatMuted'   => chat_muted_effective($row),
            'createdAt'   => iso_time($row['created_at']),
        ],
    ];
}

/**
 * POST /v1/me/referral — isang beses lang bawat account. Ang nag-input ng code
 * ang invitee; ang may-ari ng code ang kikita ng REFERRAL_COINS_REWARD coins.
 */
function me_claim_referral(array $ctx): array
{
    $uid = (string) ($ctx['user']['id'] ?? '');
    if ($uid === '') throw new ApiError(401, 'auth', 'Not signed in');

    $code = strtoupper(trim((string) (read_json()['code'] ?? '')));
    if (!preg_match('/^REF-[A-Z2-9]{6}$/', $code)) {
        throw new ApiError(400, 'invalid_referral_code', 'Invalid referral code');
    }

    $pdo = db();
    $pdo->beginTransaction();
    try {
        // Lock muna ang caller para hindi dalawang claim ang makapasok sabay.
        $caller = one('SELECT id FROM ' . T_USERS . ' WHERE id = ? AND deleted_at IS NULL FOR UPDATE', [$uid]);
        if (!$caller) throw new ApiError(401, 'unauthorized', 'Account not found');
        if (one('SELECT id FROM referrals_tracker WHERE referred_id = ?', [$uid])) {
            throw new ApiError(409, 'referral_already_claimed', 'You already used a referral code');
        }

        $referrer = one(
            'SELECT id FROM ' . T_USERS . ' WHERE referral_code = ? AND deleted_at IS NULL',
            [$code]
        );
        if (!$referrer || (string) $referrer['id'] === $uid) {
            throw new ApiError(404, 'referral_code_not_found', 'Referral code not found');
        }
        $referrerId = (int) $referrer['id'];

        run_sql(
            'INSERT INTO referrals_tracker (referrer_id, referred_id, referrer_reward, referred_reward) VALUES (?, ?, ?, 0)',
            [$referrerId, (int) $uid, REFERRAL_COINS_REWARD]
        );
        run_sql('UPDATE ' . T_USERS . ' SET coins = coins + ? WHERE id = ?', [REFERRAL_COINS_REWARD, $referrerId]);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        throw $e;
    }

    return ['ok' => true, 'reward' => REFERRAL_COINS_REWARD];
}

/** Custom token para sa world chat sign-in (uid = backend UUID). */
function account_firebase_token(array $ctx): array
{
    if (!firebase_enabled()) {
        throw new ApiError(503, 'chat_disabled', 'World chat is not configured');
    }
    return [
        'ok'    => true,
        'token' => firebase_custom_token(
            $ctx['user']['id'],
            $ctx['user']['isAdmin'],
            $ctx['user']['chatMuted'] ?? false,
            $ctx['user']['isModerator'] ?? false
        ),
    ];
}

/**
 * POST /v1/admin/chat/mute — i-mute o i-unmute ang isang user sa world chat.
 * Ang enforcement ay ang `muted` claim sa custom token (tinatanggi ng rules
 * ang create); ang client ay naghihide lang ng composer. Hindi binubura ang
 * nakaraang messages — mute lang sa pag-send. Ang manual mute ay walang
 * expiry (muted_until = NULL); ang mga timed mute ay galing sa cron.
 */
function chat_mute_user(array $ctx): array
{
    require_moderator($ctx);
    $body = read_json();

    $userId = (string) ($body['userId'] ?? '');
    $muted = ($body['muted'] ?? false) === true;
    if ($userId === '') throw new ApiError(400, 'invalid_user', 'userId is required');

    $exists = scalar('SELECT id FROM ' . T_USERS . ' WHERE id = ?', [$userId]);
    if (!$exists) throw new ApiError(404, 'user_not_found', 'User not found');

    run_sql(
        'UPDATE ' . T_USERS . ' SET chat_muted = ?, muted_until = NULL WHERE id = ?',
        [$muted ? 1 : 0, $userId]
    );
    return ['ok' => true, 'muted' => $muted];
}

/** GET /v1/admin/moderators — listahan ng moderators (Admin screen). */
function moderators_list(array $ctx): array
{
    require_admin($ctx);
    $rows = all_rows(
        'SELECT id, display_name, email FROM ' . T_USERS . '
          WHERE is_moderator = 1 AND deleted_at IS NULL
          ORDER BY display_name ASC, id ASC LIMIT 500'
    );
    return ['ok' => true, 'users' => array_map(fn ($r) => [
        'id'          => (string) $r['id'],
        'displayName' => $r['display_name'],
        'email'       => $r['email'],
    ], $rows)];
}

/** POST /v1/admin/moderators/:id — i-promote ang user bilang moderator. */
function moderator_promote(array $ctx): array
{
    require_admin($ctx);
    $userId = (string) ($ctx['params']['id'] ?? '');
    if ($userId === '') throw new ApiError(400, 'invalid_user', 'userId is required');
    $exists = scalar('SELECT id FROM ' . T_USERS . ' WHERE id = ?', [$userId]);
    if (!$exists) throw new ApiError(404, 'user_not_found', 'User not found');
    run_sql('UPDATE ' . T_USERS . ' SET is_moderator = 1 WHERE id = ?', [$userId]);
    return ['ok' => true, 'moderator' => true];
}

/** DELETE /v1/admin/moderators/:id — i-demote. */
function moderator_demote(array $ctx): array
{
    require_admin($ctx);
    $userId = (string) ($ctx['params']['id'] ?? '');
    if ($userId === '') throw new ApiError(400, 'invalid_user', 'userId is required');
    run_sql('UPDATE ' . T_USERS . ' SET is_moderator = 0 WHERE id = ?', [$userId]);
    return ['ok' => true, 'moderator' => false];
}

/** GET /v1/admin/users?search=... — hanap user para i-promote. */
function admin_users_search(array $ctx): array
{
    require_admin($ctx);
    $q = trim((string) (($ctx['query']['search'] ?? '') ?: ''));
    if (mb_strlen($q, 'UTF-8') < 2) {
        return ['ok' => true, 'users' => []];
    }
    $like = '%' . $q . '%';
    $rows = all_rows(
        'SELECT id, display_name, email FROM ' . T_USERS . '
          WHERE deleted_at IS NULL AND (display_name LIKE ? OR email LIKE ?)
          ORDER BY display_name ASC, id ASC LIMIT 20',
        [$like, $like]
    );
    return ['ok' => true, 'users' => array_map(fn ($r) => [
        'id'          => (string) $r['id'],
        'displayName' => $r['display_name'],
        'email'       => $r['email'],
    ], $rows)];
}

/** GET /v1/admin/chat/muted — listahan ng naka-mute (Admin screen). */
function chat_muted_list(array $ctx): array
{
    require_admin($ctx);
    $rows = all_rows(
        'SELECT id, display_name, email FROM ' . T_USERS . '
          WHERE chat_muted = 1 AND deleted_at IS NULL
          ORDER BY display_name ASC, id ASC LIMIT 500'
    );
    return ['ok' => true, 'users' => array_map(fn ($r) => [
        'id'          => (string) $r['id'],
        'displayName' => $r['display_name'],
        'email'       => $r['email'],
    ], $rows)];
}

/** Ang moderation settings — defaults kung wala pa ang rows. */
function moderation_settings(): array
{
    $map = [];
    foreach (all_rows('SELECT `key`, value FROM ' . T_MOD) as $r) {
        $map[(string) $r['key']] = (string) $r['value'];
    }
    return [
        'block_links' => ($map['block_links'] ?? '0') === '1',
        'mute_hours'  => max(1, min(24 * 30, (int) ($map['mute_hours'] ?? '24'))),
    ];
}

function moderation_set(string $key, string $value): void
{
    run_sql(
        'INSERT INTO ' . T_MOD . ' (`key`, value) VALUES (?, ?)
          ON DUPLICATE KEY UPDATE value = VALUES(value)',
        [$key, $value]
    );
}

/** GET /v1/admin/banned-words — ang banned word list (Admin screen). */
function banned_words_list(array $ctx): array
{
    require_admin($ctx);
    $rows = all_rows(
        'SELECT id, word, created_at FROM ' . T_BANNED . ' ORDER BY word ASC LIMIT 500'
    );
    return ['ok' => true, 'words' => array_map(fn ($r) => [
        'id'        => (int) $r['id'],
        'word'      => $r['word'],
        'createdAt' => iso_time($r['created_at']),
    ], $rows)];
}

/** POST /v1/admin/banned-words — magdagdag ng banned word. */
function banned_word_add(array $ctx): array
{
    require_admin($ctx);
    $body = read_json();
    $word = trim((string) ($body['word'] ?? ''));
    if ($word === '' || mb_strlen($word, 'UTF-8') > 100) {
        throw new ApiError(400, 'invalid_word', 'Word must be 1-100 characters');
    }
    run_sql(
        'INSERT IGNORE INTO ' . T_BANNED . ' (word, created_by) VALUES (?, ?)',
        [$word, $ctx['user']['id']]
    );
    return ['ok' => true];
}

/** DELETE /v1/admin/banned-words/:id — tanggalin ang banned word. */
function banned_word_remove(array $ctx): array
{
    require_admin($ctx);
    run_sql('DELETE FROM ' . T_BANNED . ' WHERE id = ?', [$ctx['params']['id']]);
    return ['ok' => true];
}

/** GET /v1/admin/moderation — block_links + mute_hours. */
function moderation_get(array $ctx): array
{
    require_admin($ctx);
    $s = moderation_settings();
    return ['ok' => true, 'blockLinks' => $s['block_links'], 'muteHours' => $s['mute_hours']];
}

/** POST /v1/admin/moderation — i-save ang block_links + mute_hours. */
function moderation_save(array $ctx): array
{
    require_admin($ctx);
    $body = read_json();
    $blockLinks = ($body['blockLinks'] ?? false) === true;
    $muteHours = max(1, min(24 * 30, (int) ($body['muteHours'] ?? 24)));
    moderation_set('block_links', $blockLinks ? '1' : '0');
    moderation_set('mute_hours', (string) $muteHours);
    return ['ok' => true];
}

function account_wallet(array $ctx): array
{
    $uid = $ctx['user']['id'];

    $coins = (int) (scalar('SELECT coins FROM ' . T_USERS . ' WHERE id = ?', [$uid]) ?? 0);
    $rewards = all_rows(
        'SELECT id, reward, ad_unit, created_at FROM ' . T_REWARDS . '
          WHERE user_id = ? ORDER BY created_at DESC LIMIT 50',
        [$uid]
    );

    return [
        'ok'      => true,
        'coins'   => $coins,
        'rewards' => array_map(fn ($r) => [
            'id'        => $r['id'],
            'reward'    => (int) $r['reward'],
            'adUnit'    => $r['ad_unit'],
            'createdAt' => iso_time($r['created_at']),
        ], $rewards),
    ];
}

/**
 * Anonymise, huwag burahin: nananatili ang row bilang tombstone para hindi
 * ma-reuse ang id, pero wala nang PII.
 */
function account_remove(array $ctx): array
{
    $body = read_json();
    if (($body['confirm'] ?? '') !== 'DELETE') {
        throw new ApiError(400, 'confirm_required', 'Send {"confirm":"DELETE"} to confirm');
    }

    $uid = $ctx['user']['id'];
    $now = now_utc();
    $pdo = db();

    $pdo->beginTransaction();
    try {
        $account = one('SELECT id FROM ' . T_USERS . ' WHERE id = ? FOR UPDATE', [$uid]);
        if (!$account) throw new ApiError(401, 'unauthorized', 'Account not found');
        $reelIds = array_column(all_rows('SELECT id FROM app_reels WHERE user_id = ?', [$uid]), 'id');
        run_sql('DELETE FROM ' . T_CLAIMS . ' WHERE user_id = ?', [$uid]);
        run_sql('DELETE FROM ' . T_IDEM . ' WHERE user_id = ?', [$uid]);
        run_sql("DELETE FROM feedbacks WHERE user_id = ? AND source = 'app'", [$uid]);
        run_sql('DELETE FROM app_follows WHERE follower_id = ? OR creator_id = ?', [$uid, $uid]);
        run_sql('DELETE FROM app_reel_likes WHERE user_id = ?', [$uid]);
        run_sql('DELETE FROM app_reel_comments WHERE user_id = ?', [$uid]);
        $commentIds = array_column(all_rows('SELECT id FROM app_reel_comments WHERE reel_id IN (SELECT id FROM app_reels WHERE user_id = ?)', [$uid]), 'id');
        run_sql("DELETE FROM app_reports WHERE reporter_id = ? OR (target_type = 'user' AND target_id = ?) OR (target_type = 'reel' AND target_id IN (SELECT id FROM app_reels WHERE user_id = ?))", [$uid, $uid, $uid]);
        if ($commentIds !== []) {
            $marks = implode(',', array_fill(0, count($commentIds), '?'));
            run_sql("DELETE FROM app_reports WHERE target_type = 'comment' AND target_id IN ($marks)", $commentIds);
        }
        run_sql('DELETE FROM app_reel_likes WHERE reel_id IN (SELECT id FROM app_reels WHERE user_id = ?)', [$uid]);
        run_sql('DELETE FROM app_reel_comments WHERE reel_id IN (SELECT id FROM app_reels WHERE user_id = ?)', [$uid]);
        run_sql('DELETE FROM app_reel_media WHERE reel_id IN (SELECT id FROM app_reels WHERE user_id = ?)', [$uid]);
        run_sql('DELETE FROM app_reels WHERE user_id = ?', [$uid]);
        run_sql(
            'INSERT IGNORE INTO app_cleanup_queue (uid, created_at) VALUES (?, ?)',
            [$uid, $now]
        );
        // Back to the shelf: iiwan ang status = 'claimed' ay tatambak ang key.
        run_sql(
            "UPDATE " . T_KEYS . " SET status = 'available', claimed_by = NULL, claimed_at = NULL WHERE claimed_by = ?",
            [$uid]
        );
        run_sql(
            "UPDATE " . T_USERS . " SET deleted_at = ?, email = CONCAT('deleted+', id, '@invalid'),
                    username = CONCAT('deleted+', id), display_name = '', avatar_url = NULL,
                    password = '' WHERE id = ?",
            [$now, $uid]
        );
        run_sql('UPDATE ' . T_SESSIONS . ' SET revoked_at = ? WHERE user_id = ?', [$now, $uid]);
        $pdo->commit();
    } catch (Throwable $e) {
        $pdo->rollBack();
        throw $e;
    }

    reels_delete_files($reelIds);

    // Best-effort: blanked names sa world chat. Naka-commit na ang MySQL
    // deletion bago ito, kaya kahit mag-fail dito ay tuloy ang deletion.
    if (firebase_enabled()) {
        // Revoke auth immediately; social scrubbing is retried by cron.
        firebase_delete_user($uid);
        firebase_scrub_chat($uid);
    }

    // ad_rewards sinasadya na natitira: transaction id, tombstone id, email hash
    // at oras lang ang laman — at iyon ang humahadlang sa reset ng daily ad cap.
    return ['ok' => true];
}

/**
 * GET /v1/leaderboard — Top coin holders.
 * Public, walang PII (username/display_name at coins lang).
 */
function account_leaderboard(array $ctx): array
{
    $rows = all_rows(
        'SELECT id, username, display_name, coins FROM ' . T_USERS . '
          WHERE is_banned = 0 AND deleted_at IS NULL AND coins > 0
          ORDER BY coins DESC
          LIMIT 10'
    );
    $leaders = [];
    $rank = 1;
    foreach ($rows as $r) {
        $name = trim((string) ($r['display_name'] ?? ''));
        if ($name === '') $name = trim((string) ($r['username'] ?? ''));
        if ($name === '') $name = 'Member #' . $r['id'];
        $leaders[] = [
            'rank'  => $rank++,
            'id'    => (string) $r['id'],
            'name'  => $name,
            'coins' => (int) $r['coins'],
        ];
    }
    return ['ok' => true, 'leaderboard' => $leaders];
}
