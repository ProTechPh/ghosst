# Backend main-only host cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the local PHP API push host policy accept only `ghossthub.com` (plus normalized `www.`), with no production deployment.

**Architecture:** Keep the existing `PUSH_HOST` environment override and `push_enabled()` matching logic. Change only the default, comments/log labels, and the dependency-free PHP self-check.

**Tech Stack:** PHP 8, existing `push_test.php` self-check.

**Spec:** `docs/superpowers/specs/2026-11-28-backend-main-only-design.md`

## Global Constraints

- Local source only; do not deploy to cPanel or change live environment variables.
- Do not modify DB credentials, JWT, auth, routes, CORS, `PUBLIC_CDN`, reels, or media URLs.
- `ghosst-web/` is gitignored; only tracked docs may be committed.
- Preserve `GHOSST_PUSH_HOST` override support.

## Review Focus

- **Bare production host:** `ghossthub.com` must broadcast when Firebase is configured.
- **WWW and port normalization:** `www.ghossthub.com:443` must still broadcast.
- **Retired mail host:** `mail.ghossthub.com` must stay silent.
- **Local/unrelated hosts:** localhost and unrelated domains must stay silent.
- **Disabled Firebase:** missing credentials must continue to disable push regardless of host.

---

### Task 1: Pin and apply the main-only push host policy

**Files:**
- Modify: `ghosst-web/api/config.php`
- Modify: `ghosst-web/api/lib/push.php`
- Modify: `ghosst-web/api/index.php`
- Modify: `ghosst-web/api/tests/push_test.php`
- Create: `docs/superpowers/specs/2026-11-28-backend-main-only-design.md`
- Create: `docs/superpowers/plans/2026-11-28-backend-main-only.md`

**Interfaces:**
- Consumes: `PUSH_HOST`, `push_enabled(): bool`, existing `check(bool, string): void`.
- Produces: default `PUSH_HOST = 'ghossthub.com'`; unchanged environment override and matching behavior.

- [x] Update `push_test.php` to assert `ghossthub.com` and `www.ghossthub.com:443` are allowed, while `mail.ghossthub.com`, localhost, and unrelated hosts are rejected.
- [x] Run `php ghosst-web/api/tests/push_test.php` and verify it fails on the current mail-host allowance.
- [x] Change the default `PUSH_HOST` in `config.php` to `ghossthub.com` and update its comment.
- [x] Update the host-policy comment in `lib/push.php` and the device-log comment in `index.php`.
- [x] Run `php ghosst-web/api/tests/push_test.php` and verify it prints `ok`.
- [x] Run `php -l` on the three modified PHP source files and verify no syntax errors.
- [x] Confirm no live deployment was performed and no secrets or unrelated backend files changed.
- [x] Commit only the tracked design/plan docs; leave gitignored backend edits local.
