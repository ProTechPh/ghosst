# Referral rewards: equal backend credit + no delete/re-register reuse

## Intent
Ang bawat valid referral claim ay magbigay ng **5 app coins sa referrer at 5 app coins sa invitee**. Ang API lamang ang mag-credit. Hindi maaaring mag-claim muli ang parehong email/account identity kahit na-delete at mag-register muli, upang maiwasan ang reward farming.

## Goals
- Backend transaction ang mag-update ng dalawang `users.coins` at mag-record ng dalawang reward values sa `referrals_tracker`.
- Ang `POST /v1/me/referral` ang magbalik ng aktwal na reward; app display lang at walang hardcoded reward amount.
- Mananatili ang referral eligibility marker pagkatapos ng account deletion; raw email ay hindi itatago sa tracker.
- Self-referral, malformed code, deleted referrer, duplicate claim, at concurrent duplicate claim ay mananatiling blocked.

## Non-goals
- Walang reward sa website `referral_balance`; frozen pa rin ito.
- Walang deep link, QR, o device binding.
- Walang rebate/refund kapag nag-delete ang invitee; naipagkaloob na coins ay nananatili.
- Hindi ibig sabihin ng “same reward” na pwedeng mag-claim nang higit sa isang beses bawat email identity.

## Constraints
- Coins/stock mutations ay API-only.
- Lock order ay deterministic para hindi mag-deadlock ang magkasintang reciprocal claims.
- Ang migration ay additive; may checked-in SQL at lazy API safeguard.
- Ang deployment ay manual upload sa Hostinger; hindi ito binuo mula sa Flutter repo.
- Ang `ghosst-web/` ay intentionally gitignored; backend edits ay deploy artifacts at hindi isasama sa app repo commits.
- Flutter verification: `flutter analyze`, `flutter test`; huwag `flutter run`.

## Approaches considered
1. **Email-hash marker sa `referrals_tracker` (selected).** Stable across delete/re-register, walang raw email, compatible sa existing ad-reward email-hash pattern. Kailangan ng additive column at unique index.
2. **Device/install binding.** Madaling ma-reset at hindi aabot sa lahat ng install/account; mas mahina laban sa reuse.
3. **User ID only (current).** Hindi sapat dahil bagong account ay may bagong ID pagkatapos ng deletion.

## Design

### API contract
`POST /v1/me/referral` body remains `{"code":"REF-XXXXXX"}`. Success response remains:

```json
{"ok":true,"reward":5}
```

`reward` is the amount credited to **each** participant. The app must use this value for display and must not carry a fallback reward constant.

### Claim transaction
1. Normalize at validate ang referral code.
2. Hanapin ang active caller at active referrer mula sa code.
3. I-lock ang dalawang user rows sa ascending `users.id` order; i-revalidate ang caller, referrer, at code pagkatapos ng lock.
4. Compute `referred_email_hash = sha256(mb_strtolower(trim(caller.email), UTF-8))`.
5. Block kung may existing tracker row para sa `referred_id` o `referred_email_hash`.
6. Iinsert ang tracker row na may `referrer_reward = referred_reward = REFERRAL_COINS_REWARD` at ang email hash; ang unique-key race ay `409 referral_already_claimed`.
7. I-update ang coins ng referrer at invitee sa iisang transaction.
8. Icommit; rollback sa anumang error. Ang migration/index failure ay `503 referral_unavailable` at hindi nagpapatuloy sa claim.

### Persistent identity / migration
- Idagdag ang `referrals_tracker.referred_email_hash CHAR(64) NULL`.
- Idagdag ang unique index `uq_referred_email`.
- Backfill ng active accounts gamit ang parehong PHP `mb_strtolower()` canonicalizer na ginagamit sa claim.
- Lazy safeguard sa API bago ang claim transaction at bago anonymize sa account deletion; fail closed kung hindi mave-verify ang column o unique index.
- Sa deletion, panatilihin ang tracker row at siguraduhing may hash ang mga lumang claim rows bago mawala ang email.
- Hindi mahuhuli nang lubos ang mga deleted accounts bago ang deployment na wala nang orihinal na email at wala ring `app_ad_rewards.email_hash`; ito ay kilalang limitation.

### Flutter
- `Backend.claimReferral()` returns the API `reward`; tanggalin ang `referralReward = 100` constant at fallback.
- `ReferralSheet` snackbar: `You and your friend earned <server reward> coins each`.
- Walang local coin write o optimistic reward credit.

## Tests
- PHP self-check: equal credit values, email-hash normalization, duplicate-by-id, duplicate-by-hash, unique-key race, migration failure, invalid/self/deleted referrer, deterministic lock ordering, at `account_remove()` preserves tracker/hash before anonymization.
- Opt-in live integration script: concurrent duplicate, reciprocal claims, at delete/re-register reuse sa dedicated multi-worker test API.
- Flutter referral tests: server-provided reward amount ang ipinapakita; walang hardcoded amount.
- Existing PHP tests, `flutter test`, `flutter analyze`, at PHP syntax checks.

## Deploy
1. I-upload ang bagong `api/` files.
2. I-run ang additive migration sa `ghosst-web/database/mobile_app_referral_identity.sql`.
3. I-verify ang column at unique index.
4. I-smoke-test gamit ang dalawang active accounts: both balances +5, replay blocked, delete/re-register with the same email blocked.
5. I-release ang Flutter app na gumagamit ng server reward value.
