# Google sign-in sa app (2026-11-13)

## Bakit

Ang web ay may Google login na (`auth/google-login.php` → `google-callback.php`),
pero ang app ay email+password lang at may sariling sign-up form. Gusto ng
may-ari na ang paggawa ng bagong account sa app ay dumaan sa Google, tulad ng
web — isang account, isang identity.

## Desisyon

- **Pinili:** Google ang pangunahing paraan (landing + sign-in screen); tinanggal
  ang `lib/sign_up.dart`. Mananatili ang email+password **sign-in** para sa
  5,202 live accounts na may coins/claims (walang password reset sa app).
- **Hindi pinili:** (a) Firebase Auth `signInWithCredential` — kailangan pa rin
  ng Google credential, at nakikipag-agawan sa custom-token session ng world
  chat; (b) WebView sa `google-login.php` — kailangan ng bagong token handoff
  sa website at mas maraming mababasag.

## Paano

1. App: `google_sign_in` → Google ID token (`serverClientId` = web client ID
   na `578056640322-…`, pareho ng nasa `config/google_oauth.php`).
2. `POST /v1/auth/google {idToken}` — `api/lib/auth.php` `google_claims()` ang
   nagbe-verify sa `oauth2.googleapis.com/tokeninfo` (Google na ang sa
   signature/iss/exp) at sinisigurong `aud` = `GOOGLE_CLIENT_ID`.
3. Meron nang `users` row sa email → login (hindi ginagalaw ang password).
   Wala pa → bagong row: username mula sa Google name, **random password**,
   `display_name`, referral code. Pareho ng ginagawa ng web callback.
4. Session: parehong JWT + refresh token; `id` ay string pa rin.

## Config na kailangan sa Google Cloud (project 578056640322)

Dalawang Android OAuth client (release SHA-1 `6B:69:…:C5`):
`com.astrixtech.ghosst` at `com.astrixtech.ghosst.direct`. Debug SHA-1 kung
mag-tetest sa debug build. Walang kailangang baguhin sa `google-services.json`.

## Trade-off

Ang bagong app user ay hindi makakagawa ng email+password account sa app;
makakapasok sila sa website via Google o email reset. Ang existing users na
hindi pareho ang Google email ay email sign-in pa rin ang gagamitin.
