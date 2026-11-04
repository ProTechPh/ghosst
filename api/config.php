<?php
/**
 * Config ng mobile API.
 *
 * Ang DB credentials ay pareho ng `includes/db_config.php` (hindi natin siya
 * ini-include kasi nag-start yun ng PHP session sa bawat API call). Kapag
 * pinalitan mo ang password sa isang file, palitan din dito.
 */

declare(strict_types=1);

define('DB_HOST', getenv('GHOSST_DB_HOST') ?: 'localhost');
define('DB_NAME', getenv('GHOSST_DB_NAME') ?: 'khctcfuv_ghosst');
define('DB_USER', getenv('GHOSST_DB_USER') ?: 'khctcfuv_ghost_premium');
define('DB_PASS', getenv('GHOSST_DB_PASS') ?: 'PC7HGhN]u{,#XjI.');

/** Pumirma ng access token. Palitan ito ng sarili mong random string. */
define('JWT_SECRET', getenv('GHOSST_JWT_SECRET') ?: 'a4f8c2e61b9d47a0e3c5b7d9f1a2c4e68b0d3f5a7c9e1b2d4f6a8c0e2b4d6f8a');
define('ACCESS_TTL', 3600);

/** Default coins kapag walang reward_amount ang SSV callback. */
define('COINS_PER_REWARD', (int) (getenv('COINS_PER_REWARD') ?: 10));

/** AdMob reward verification keys. */
define('ADMOB_KEY_URL', getenv('GHOSST_ADMOB_KEY_URL') ?: 'https://gstatic.com/admob/reward/verifier-keys.json');

/** Cloudinary cleanup (opsyonal). Walang laman = laktawan ang delete. */
define('CLOUDINARY_CLOUD', getenv('CLOUDINARY_CLOUD_NAME') ?: '');
define('CLOUDINARY_KEY', getenv('CLOUDINARY_API_KEY') ?: '');
define('CLOUDINARY_SECRET', getenv('CLOUDINARY_API_SECRET') ?: '');

/** Public CDN prefix para sa mga image key na hindi buong URL. */
define('PUBLIC_CDN', getenv('PUBLIC_CDN') ?: '');

/** OneSignal push. Blank REST key = feature off. */
define('ONESIGNAL_APP_ID', getenv('GHOSST_ONESIGNAL_APP_ID') ?: '');
define('ONESIGNAL_REST_KEY', getenv('GHOSST_ONESIGNAL_REST_KEY') ?: '');
/** Only this host may broadcast (GHOSST_PUSH_HOST override). */
define('PUSH_HOST', getenv('GHOSST_PUSH_HOST') ?: 'ghossthub.com');

define('ALLOWED_ORIGINS', 'https://ghosst.app,https://app.ghosst.app');

/** Tabla ng mobile app — lahat may app_ prefix. */
define('T_USERS', 'app_users');
define('T_SESSIONS', 'app_sessions');
define('T_PRODUCTS', 'app_products');
define('T_IMAGES', 'app_product_images');
define('T_DURATIONS', 'app_product_durations');
define('T_FILES', 'app_product_files');
define('T_KEYS', 'app_keys');
define('T_CLAIMS', 'app_claims');
define('T_REWARDS', 'app_ad_rewards');
define('T_IDEM', 'app_idempotency');
define('T_ANNOUNCEMENTS', 'app_announcements');
