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

/** Google Sign-In: ang `aud` na sinusuri ng /v1/auth/google (parehong web client
 *  ng website sa ghosst-web/config/google_oauth.php). Blank = naka-off. */
define('GOOGLE_CLIENT_ID', getenv('GHOSST_GOOGLE_CLIENT_ID')
    ?: '578056640322-1lkus4sngk496sn29fqmor6ab13nkgfk.apps.googleusercontent.com');

/** Default coins kapag walang reward_amount ang SSV callback. */
define('COINS_PER_REWARD', (int) (getenv('COINS_PER_REWARD') ?: 10));

/** AdMob reward verification keys. */
define('ADMOB_KEY_URL', getenv('GHOSST_ADMOB_KEY_URL') ?: 'https://gstatic.com/admob/reward/verifier-keys.json');

/** Play Integrity API (observe-only). Blank SA = /v1/integrity/check is 503. */
define('PLAY_INTEGRITY_SA_EMAIL', getenv('GHOSST_PLAY_INTEGRITY_SA_EMAIL') ?: '');
define('PLAY_INTEGRITY_SA_KEY', getenv('GHOSST_PLAY_INTEGRITY_SA_KEY') ?: '');
/** Play package name (the `direct` flavor is never attested). */
define('PLAY_INTEGRITY_PACKAGE', 'com.astrixtech.ghosst');

/** Force-update gate. 0 = off; set to the published version code when live. */
define('APP_MIN_VERSION_CODE', (int) (getenv('GHOSST_APP_MIN_VERSION') ?: 0));
define('APP_LATEST_VERSION_CODE', (int) (getenv('GHOSST_APP_LATEST_VERSION') ?: 0));
define('APP_PLAY_URL', getenv('GHOSST_APP_PLAY_URL')
    ?: 'https://play.google.com/store/apps/details?id=com.astrixtech.ghosst');
define('APP_DIRECT_URL', getenv('GHOSST_APP_DIRECT_URL')
    ?: 'https://ghossthub.com');

/** Public base URL para sa uploads/products image keys. */
define('PUBLIC_CDN', getenv('PUBLIC_CDN') ?: '');

/** Public storefront, for premium-shop links and images. */
define('SHOP_URL', getenv('GHOSST_SHOP_URL') ?: 'https://ghossthub.com');

define('REEL_UPLOAD_SECRET', '3b43034bff940a247b1ceafd4802bff09af77419bd047ca94f53c34c9acd43f6');
define('REEL_PUBLIC_BASE_URL', 'https://ghossthub.com/reels/media');
define('REEL_UPLOAD_URL', 'https://ghossthub.com/reels/upload.php');

/** Firebase world chat. Blank service account = feature off. */
define('FIREBASE_PROJECT_ID', getenv('GHOSST_FIREBASE_PROJECT_ID') ?: 'ghosst-6f23e');
define('FIREBASE_SA_EMAIL', getenv('GHOSST_FIREBASE_SA_EMAIL') ?: 'firebase-adminsdk-fbsvc@ghosst-6f23e.iam.gserviceaccount.com');
define('FIREBASE_SA_KEY', getenv('GHOSST_FIREBASE_SA_KEY') ?: 'LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JSUV2Z0lCQURBTkJna3Foa2lHOXcwQkFRRUZBQVNDQktnd2dnU2tBZ0VBQW9JQkFRQ2dHN1lUWktuMU85V0MKd1ZQNkkwbWdXcDZYTlQwK1lEUHErcUF3MWYvYUNXRXpCd1Q3YzdRUTNFRDA3WkU4NHBkUU1QcE40NzhpYmtYUApJQ1lWbENKM0VQRm4zSXQvTVYzUGcyY2t4Q1BGYmE2VDF0Z0FoYjI0OG9kS1Y0YitIT2M4M2lVTGZvM2sxY2s1CnhIbTdkeTYyWnNyNCt1MWJjY3dEMys4T2xOcmJVR0pZMW1QQjF2VjNveEkvZmNVdDJiemNuMW5xa0Izd3Q1WVUKYXF2d1V5eHVFZm5nRVlwd21lSXdyZFp0WU1NdUovTFFXSkhxRUVxVGc0bHdHeDRqcG9CSFE5NWhoeFNUUmtRTwpnNzJUYVdUM3NzOWtIWlppa2hoazY1Nk1wZXZvWUovYS96Q2NQd3BJaFVIRkZUcmY4Rko0T3F2aXNqNDZaeUMzCkRuZVNqdlhYQWdNQkFBRUNnZ0VBSnJaTWtlZlhDRXFOVjI0elJkbmVaWDFEdHovU0xSREp2TmtZZm5aZnhISmMKSkNCZ1hnUWQxNjNKcnU3NkhRU1VuWGthTEZjUzBkcGoycTdsUm5abzF1MHIwWGNMNjVjZUhaeWlCY3UrOG0rUQp0SUpQKytCYWZTdDI5c3l2QVNZdjZ4R3pWMUlrTU41WUp6V1FVWG1CdSt5aXl3eXc4MWxTZ09WV1FlcFArSkxYCkVhZ2oyRVNwTGJXVnV1RWtSOW5XcWp1SEdNWlpqV0sxUzJCWDlmcDQxc3hPN0w4YkVJUlVRbk83RE0zT3ppSTAKTGVmWWlpT1o0Y1lhNC9GZ04wQzlsWFVPdkw3OUxaM2FjMHZqYndtekFTZUQveXNiN2U1WjAybFE2NHJQWHVrbAo5SXNxZUQvSVppNmdnR3dQU0hSdE9TVGVxVjZKRzRjZGRkaTRpak55MFFLQmdRRFVPUEJrdEJhaGc4cUxpS2ErCkY4QjU1Y2FLcXVHYjMzc0JhTWVVTi8yemxJRHZBdVpKK2FEbnNmc0VCL0VXZy9XUEpzY29mcSs2eDF1aVI1U0UKc1lGZWRZb2xHOWY1T3hXQUhKc0lKUnRYR1QrQ3VjQ3lHYVpsOFBRVUlTSXlxNDlSaGh6V09ETGQ0TlpMRWxabQpiTG9pZUlreDlUTVp6ZGp5WDAvVHFWNmZ2UUtCZ1FEQklyamw4UVRGaFFvQTMrU2s2TlE4cVphVk5weDVKMTJQCkxSenl1QUQzTXBqZHZhSUhzMDZYRDdYZC9Md1lwaXlKTkxzbWdPMGxnU0ZFdXV3dXZxeWhnbE8yK3pZckFXczMKQktUWUJWOXYwblJoSTd6RjVVMG1wYXpWRTZwU0NtKzJlWkpGSTc2ZDJYZFliQW8zV0g3RFlFMDM2Wm1ZNTNaNwpLYXFSbytvTEl3S0JnUUN2RndNT3NwM3hSOEIxK3BwSFAyVm5yTEZ2ZXFpRVo0OGVqSW9NdVYweEtoWnVHMkJRCkxBb2EzbmFRenRTVGxPK2wyWUo2NEhxdmlRY0xEaTkwZ3RhUFRqNVplMjFtak42aVFmZU9jcjdwejBUYzM5QWgKb0pQdWl5dDA2QmxFNE5Kdm1reDBXUTF1amE5L1pIT3dNWWdvSkhaY3AwWXZ4ZXQxbkRsS0VmU2xxUUtCZ0VvbApVbWEwaU9ocmt0T1RJT3hPbG14VGp3UHAyMWlIekZ0VExuSGdRajZrcGhzNjJpR3FyTmxCcHNoNlpwdnY3OWtjCjdWeHkwcGc3WXRKSUVMUkJiM1R4MjhHNzM2ZlMrNTQ3b2kxc29wOERaTHFHUmNxVHBYTFkxK2xWaTJYRHErK1oKN0pXdWkxZCtUVnNjM3k4d1Fqb3ZsbldJc1BjS3BXblRMVENNaFNXUkFvR0JBSUdEb2dnYldRdFhkbTFSc04vKwo4SmZWN1RjZ0hZSG5ycUtEc0MxdStLY0hMRnlaTWFLRE55VWowNzJQRkdqQVFQKzdjZ3ZOUW9VWHJoendCQlpmCmgveklFS0Y5UGxtdFVOVm1pay9Kb0M0VTJ4REpiUzNBUnlRa2VHWTNVOGhTbDUxdE1Lb3ZNMFZHZjNCRWFEYTQKYm9nY2FRT29UdEVXZ0psYjVqb1IwRUcyCi0tLS0tRU5EIFBSSVZBVEUgS0VZLS0tLS0K'); // base64 ng PEM

/** Broadcast push: direct FCM topic message (walang Novu na dumadaan). */
define('PUSH_TOPIC', getenv('GHOSST_PUSH_TOPIC') ?: 'ghosst');
/**
 * Only these hosts may broadcast (GHOSST_PUSH_HOST override, comma-separated).
 * The app's base URL is mail.ghossthub.com, the website is ghossthub.com —
 * both are production and must be able to send.
 */
define('PUSH_HOST', getenv('GHOSST_PUSH_HOST') ?: 'ghossthub.com,mail.ghossthub.com');

define('ALLOWED_ORIGINS', 'https://ghosst.app,https://app.ghosst.app');

/** Tabla ng mobile app — accounts ay nasa website `users` na; ang iba ay app_ prefix. */
define('T_USERS', 'users');
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
define('T_BANNED', 'app_banned_words');
define('T_MOD', 'app_moderation');
define('T_MODERATORS', 'app_moderators');
