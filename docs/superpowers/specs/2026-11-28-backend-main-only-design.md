# Backend main-only host cleanup design

## Intent
Align the local PHP API source with the app's `ghossthub.com`-only host decision without deploying to production yet.

## Goals
- Default `PUSH_HOST` to `ghossthub.com` only.
- Keep `www.ghossthub.com` accepted through the existing hostname normalization.
- Reject `mail.ghossthub.com` in the push host self-check.
- Remove obsolete mail-host comments and log labels.

## Non-goals
- No live cPanel deployment or environment-variable change.
- No database, JWT, auth, route, CORS, `PUBLIC_CDN`, reel, or media URL changes.
- No removal of the cPanel mail subdomain or certificate.

## Constraints
- `ghosst-web/` is gitignored; backend edits remain local source changes.
- `GHOSST_PUSH_HOST` remains a supported environment override.
- The existing PHP self-check must stay dependency-free and runnable with local PHP 8.

## Approaches
1. Keep `ghossthub.com,mail.ghossthub.com` in `PUSH_HOST`: preserves old behavior but leaves stale host policy. Not chosen.
2. Local main-only cleanup, deploy later (chosen): updates source/tests now without touching production.
3. Local cleanup plus immediate live deploy: rejected for this step by the owner.

## Design
- In `ghosst-web/api/config.php`, change the default `PUSH_HOST` to `ghossthub.com` and update its comment.
- In `ghosst-web/api/lib/push.php`, update the host-policy comment only.
- In `ghosst-web/api/index.php`, update the device-log comment only.
- In `ghosst-web/api/tests/push_test.php`, assert `ghossthub.com` and `www.ghossthub.com` are allowed, while `mail.ghossthub.com`, localhost, and unrelated hosts are rejected.
- Verify with `php ghosst-web/api/tests/push_test.php`.
