# Referral → 100 coins (app-only)

## Intent
Ang referral earning ay ililipat sa app: ang nag-imbita ay makakakuha ng **100 app coins**.
Sa website, **patitigilin ang pag-earn** at tanggalin ang referral/claim flow, pero ang
existing `referral_balance` ay **i-freeze** — nananatiling nakikita at magagastos sa
checkout para hindi mawalan ng halaga ang mga users (pinili ng user: option C).

## Goals
- App: maipakita ang sariling `referral_code` (Copy/Share) at mag-input ng code ng
  nag-imbita sa Profile; 100 coins ang mapupunta sa referrer.
- Website: walang bagong `referral_balance` na kikita; walang referral page o claim endpoint.
- Reuse ang umiiral na `users.referral_code` at `referrals_tracker` — walang DB migration.
- Ang API ang tanging nagsusulat ng coins; walang binabayaran ang website.

## Non-goals
- Walang deep link / sign-up field / QR. Manual input sa Profile lang.
- Walang reward sa invitee; 100 coins sa referrer lang.
- Hindi ini-convert ang existing `referral_balance` sa coins o site balance — frozen lang.
- Walang wallet-history row para sa referral; tataas lang ang balance.

## Constraints
- Coins ay server-side lang (`routes/ads.php` ang precedent).
- Lock order: user row bago ang ibang row (deadlock rule ng claims).
- Ang API ay nasa `ghosst-web/api/` at ina-upload sa Hostinger; walang deploy mula sa repo.
- `referral_balance` ay may 2 decimals at ginagastos sa `checkout.php` gamit ang
  `referral_coin_rate` at `allow_referral_pay` — hindi ito binabago.

## Approach
I-port ang website referral mechanics (code generation + tracker) sa API, at tanggalin
ang website-side earning/claim. Ang alternatibong tumawag ng website endpoints ay hindi
gagana (session/cookie, HTML, site balance ang bayad), at ang referral-link cookie ay
hindi naaabot ng app (`/v1/auth/google` ay ID-token based).

## Design

### Website — tanggalin (walang bagong earning)
1. `ajax/auth.php` — tanggalin ang referral processing block (~108-162). **Panatilihin**
   ang pag-generate ng `referral_code` sa INSERT (~86-103) kailangan ito ng app.
2. `auth/google-callback.php` — tanggalin ang referral processing block (~138-182).
   Panatilihin ang code generation (~118-134).
3. `ajax/redeem_referral.php` — burahin (claim endpoint).
4. `referrals.php` — burahin (user referral page: invite link + stats + redeem).
5. Tanggalin ang links sa `referrals.php` sa `dashboard.php`, `gifts.php`, `profile.php`,
   at `admin/includes/layout.php`.
6. `includes/db_config.php` — tanggalin ang `?ref=` → `referred_by` session/cookie capture
   (~292-297); wala nang consumer nito.

### Website — panatilihin (frozen value, option C)
- `users.referral_balance` column, sidebar balance display sa lahat ng pahina.
- `checkout.php` "Referral Coins" payment path, `referral_coin_rate`, `allow_referral_pay`.
- `admin/referrals.php`, admin settings section, `admin/users.php` balance adjust —
   ang reward settings ay hindi na ginagamit sa pag-compute (walang nag-e-earn), pero
   ang coin rate at product rules ay kailangan pa rin ng checkout.

### API (`ghosst-web/api/`)
7. `config.php`: `define('REFERRAL_COINS_REWARD', 100);`
8. `routes/account.php`:
   - `account_me()` — idagdag ang `referral_code` sa SELECT at i-output bilang
     `referralCode`.
   - Bagong `me_claim_referral($ctx)` — `POST /v1/me/referral`, body `{"code":"REF-XXXXXX"}`:
     - Trim + uppercase; format `REF-[A-Z2-9]{6}` (parehong alphabet ng
       `unique_referral_code()`).
     - Hanapin ang referrer sa `users` (`deleted_at IS NULL`); tanggapin lang kung
       hindi sarili at walang existing `referrals_tracker` row para sa caller
       (isang claim bawat account).
     - Sa transaction: `SELECT ... FOR UPDATE` ang caller row, isingit sa
       `referrals_tracker (referrer_id, referred_id, referrer_reward, referred_reward)`
       na `(referrer, caller, 100, 0)`, pagkatapos `UPDATE users SET coins = coins + 100
       WHERE id = referrer`. Ibalik ang bagong coins + `ok`.
9. `index.php`: route `['POST', '#^/v1/me/referral$#', 'me_claim_referral', 'required']`.

### Flutter (`lib/`)
10. `services/worker_backend.dart` — `AppUser.referralCode` (default `''`).
11. `services/worker_backend.dart` — i-parse ang `referralCode` sa `_me()` at idagdag ang
    `static Future<int> claimReferral(String code)` (POST `/me/referral`, ibalik ang coins).
12. `screens/profile_screen.dart` — **Referral** row sa Account group na nagbukas ng sheet:
    sariling code + Copy/Share, at code field + Claim. Result snackbar at balance refresh.
    Gamitin ang umiiral nang `CardFrame`/`AppText`/SnackBar patterns; walang bagong package.

### Tests
13. Backend test para sa `claimReferral` (success + invalid/self code) at widget test para
    sa referral sheet. `flutter test`, walang network.

## Risks / calls
- Walang DB-level UNIQUE sa `referrals_tracker.referred_id`; ang transaction lock sa
  caller row ang guard. Sabay na website insert ay hindi na mangyayari pagkatapos tanggalin
  ang earning doon.
- Frozen `referral_balance` ay hindi na mapapalaki; ang mga users na may luma nang balance
  ay gastos pa rin nila sa checkout hangga't naka-on ang `allow_referral_pay`.
- Ang 100 ay fixed, hindi admin-tunable — wala nang settings dependence.
- Ang pagtanggal ng `referrals.php` ay mawawalan ng history view; ang app sheet ay
  magpapakita lang ng code at claim result, hindi ng invite list.
- Ang code format para sa claim ay pinalawak sa `(REF-)?[A-Z0-9]{4,12}` para
  magamit ang lumang codes na may `0`/`1` o walang prefix; ang bagong generasyon
  ay nananatiling `REF-[A-Z2-9]{6}`.

## Deploy checklist (Hostinger)
Ang repo ay hindi nagde-deploy ng website; kailangang i-upload nang manual:

1. I-upload ang binagong API: `config.php`, `routes/account.php`, `index.php`.
2. Burahin sa Hostinger ang `ajax/redeem_referral.php` at `referrals.php`.
3. I-upload ang binagong website files: `ajax/auth.php`, `auth/google-callback.php`,
   `includes/db_config.php`, `dashboard.php`, `gifts.php`, `profile.php`,
   `settings.php`, `admin/includes/layout.php`.
4. Kumpirmahin na `GET /v1/me` ay may `referralCode`, at `POST /v1/me/referral`
   ay umiiral (hindi 404).
5. Two-user smoke bago i-release: sariling code → walang kredito; replay → 409;
   deleted referrer → 404; valid legacy code (hal. may `0`) → 200 at +100 coins.
   Ito ang release gate — walang automated DB test para sa handler sa repo.
6. Huwag galawin ang `referral_balance`, `checkout.php`, `referral_coin_rate`,
   o `allow_referral_pay` — frozen value lang ang requirement.
