# ghossthub.com-only API design

## Intent
Make `https://ghossthub.com/api/v1` the only API host used by new Ghosst builds, removing the dual-host client and the need for the `mail.ghossthub.com` origin hostname.

## Goals
- New builds send API, refresh, and relative media requests only to `ghossthub.com`.
- Keep the IPv4-first socket behavior and normal TLS validation.
- Keep the existing auth, retry, timeout, and error behavior.
- Remove obsolete mail-host documentation and client fallback code.

## Non-goals
- No backend, database, Cloudflare, SSL, or cPanel configuration change in the app-code step.
- No staged retention of the mail DNS record; the owner chose immediate deletion.
- No change to AdMob SSV, which already calls `ghossthub.com`.

## Constraints
- `ghossthub.com` is Cloudflare-proxied; the origin host was originally introduced to avoid Cloudflare 403s on shared mobile-data IPs.
- Older app versions may still use `mail.ghossthub.com` directly or as their primary host.
- The owner explicitly accepts that deleting the mail DNS record immediately can lock out older versions without a working fallback.

## Approaches
1. **Keep dual host (current):** origin first, Cloudflare fallback. Most resilient, but keeps extra client and DNS complexity. Not chosen.
2. **Main-only and delete mail DNS immediately (chosen):** simplest end state. The owner accepts the compatibility risk for older installed versions.
3. **Main-only app now, staged DNS retirement:** safer for old installs, but leaves the mail record temporarily. Not chosen.

## Design
- `ApiConfig.baseUrl` defaults to `https://ghossthub.com/api/v1`.
- Remove `fallbackBaseUrl`, `baseUrls`, and the second Dio/fallback retry path.
- Keep one production Dio for API requests plus the existing bare refresh Dio, both using the IPv4-first TLS adapter.
- `ApiConfig.publicUrl()` continues resolving relative upload keys through `baseUrl`, so media moves to `ghossthub.com` automatically.
- Update `SETUP.md` so `ghossthub.com` is the sole documented app API/push host.
- Add/update focused tests for the single-host configuration and preserved IPv4-first behavior.
- Delete the Cloudflare `mail.ghossthub.com` DNS record immediately after the main-only client is verified, as explicitly approved by the owner.

## Rollout
1. Implement and verify the main-only client.
2. Build the release candidate before changing DNS.
3. Delete the Cloudflare `mail.ghossthub.com` DNS record.
4. Verify `ghossthub.com` still resolves and serves the API.
5. Distribute the new app and watch PHP device logs and Cloudflare security events for `ghossthub.com` 403s or transport failures.
