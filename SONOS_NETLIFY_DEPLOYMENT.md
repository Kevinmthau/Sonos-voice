# Sonos + Netlify Deployment Checklist

This document wires the `SonosVoiceRemote` app to `https://sonos-voice.netlify.app/` using Netlify Functions as the Sonos OAuth broker.

## 1. Sonos Developer Portal

Create or update your integration key with these exact values:

- Key Name: `SonosVoiceRemote iOS - sonos-voice.netlify.app`
- Redirect URI: `https://sonos-voice.netlify.app/sonos/oauth/callback`
- Event Callback URL: `https://sonos-voice.netlify.app/sonos/events`

Notes:

- The redirect URI must stay public and HTTPS.
- The event callback URL is optional for basic control, but this repo already exposes it.
- Sonos redirect URIs and event callback URLs are different endpoints.

## 2. Netlify Site

These files are already in this repo:

- [netlify.toml](/Users/kevinthau/sonos-voice/netlify.toml)
- [sonos-auth-start.js](/Users/kevinthau/sonos-voice/netlify/functions/sonos-auth-start.js)
- [sonos-auth-callback.js](/Users/kevinthau/sonos-voice/netlify/functions/sonos-auth-callback.js)
- [sonos-events.js](/Users/kevinthau/sonos-voice/netlify/functions/sonos-events.js)
- [_sonos-oauth.js](/Users/kevinthau/sonos-voice/netlify/functions/_sonos-oauth.js)

Important:

- These files must be deployed by the Netlify site that actually serves `sonos-voice.netlify.app`.
- If `sonos-voice.netlify.app` uses a different repo, copy `netlify.toml` and the `netlify/functions` folder into that repo.

## 3. Netlify Environment Variables

In Netlify:

1. Open the `sonos-voice.netlify.app` site.
2. Go to `Site configuration` -> `Environment variables`.
3. Add:

**Required**

- `SONOS_CLIENT_ID` (no default — the build-time fallback has been removed)
- `SONOS_CLIENT_SECRET`
- `SONOS_STATE_SECRET` (random string ≥32 bytes)
- `SONOS_ALLOWED_HOUSEHOLDS` — comma-separated Sonos household IDs allowed to use this deployment. If unset the proxy will accept any household, which is **only** appropriate for first-run testing. Set this to your friends-and-family household IDs (find one by signing in once and copying it out of `/households` response) before sharing the URL.

**Required if OpenAI transcription is enabled**

- `OPENAI_API_KEY`
- `SONOS_OPENAI_TRANSCRIPTION_TOKEN`

**Optional**

- `SONOS_REDIRECT_URI=https://sonos-voice.netlify.app/sonos/oauth/callback`
- `SONOS_IOS_CALLBACK_URL=sonosvoiceremote://oauth/callback`
- `SONOS_PROXY_ALLOWED_ORIGIN` — CORS origin for `/api/sonos` and `/api/sonos/refresh`. Defaults to `https://sonos-voice.netlify.app`. Set this if you host the SPA on a custom domain.
- `SONOS_TRANSCRIPTION_ALLOWED_ORIGIN` — CORS origin for `/api/transcribe`. Defaults to `https://sonos-voice.netlify.app`.
- `TRANSCRIBE_PER_IP_DAILY_CAP` — daily transcription request cap per IP. Default `200`.
- `TRANSCRIBE_GLOBAL_DAILY_CAP` — daily transcription cap across the deployment. Default `2000` (~$0.60/day at `gpt-4o-mini-transcribe` for typical voice commands).
- `SONOS_REFRESH_PER_IP_DAILY_CAP` — daily Sonos token-refresh cap per IP. Default `60`.

Recommended:

- Generate `SONOS_STATE_SECRET` as a long random string, at least 32 bytes of entropy.
- Do not expose `SONOS_CLIENT_SECRET` in client-side code.
- Do not expose `OPENAI_API_KEY` in client-side code; the iOS app sends audio to the Netlify function at `/api/transcribe`.
- Generate `SONOS_OPENAI_TRANSCRIPTION_TOKEN` as a long random string and set the same value in the iOS launch environment so the transcription proxy rejects unauthenticated calls before using the OpenAI key.
- The web controller now defaults to the same registered Sonos redirect URI as iOS. You only need `SONOS_WEB_REDIRECT_URI` if you explicitly register a second web-specific callback URL with Sonos.

**Netlify Blobs** is used by the transcription and refresh endpoints to track daily rate-limit counters. No setup is needed beyond deploying to Netlify — the `transcription-rate-limits` and `sonos-refresh-rate-limits` stores are auto-provisioned.

## 4. Netlify Routing

After deploy, these routes should exist:

- `https://sonos-voice.netlify.app/`
- `https://sonos-voice.netlify.app/privacy`
- `https://sonos-voice.netlify.app/sonos/oauth/start`
- `https://sonos-voice.netlify.app/sonos/oauth/callback`
- `https://sonos-voice.netlify.app/sonos/oauth/start/web`
- `https://sonos-voice.netlify.app/sonos/oauth/callback/web`
- `https://sonos-voice.netlify.app/sonos/events`
- `https://sonos-voice.netlify.app/api/sonos` (POST only)
- `https://sonos-voice.netlify.app/api/sonos/refresh` (POST only)
- `https://sonos-voice.netlify.app/api/transcribe` (POST only)

Expected behavior:

- `/` serves the web controller SPA.
- `/privacy` serves the privacy notice page (SPA route).
- `/sonos/oauth/start` redirects to Sonos login (iOS flow).
- `/sonos/oauth/callback` exchanges the Sonos auth code for tokens and redirects into the iPhone app.
- `/sonos/oauth/start/web` and `/sonos/oauth/callback/web` mirror the iOS flow for the browser SPA.
- `/sonos/events` returns `200 OK` and can later be expanded to verify/store Sonos events.
- `/api/sonos` proxies Sonos Control API calls; enforces method/path validation, the household allowlist, and `SONOS_PROXY_ALLOWED_ORIGIN` CORS.
- `/api/sonos/refresh` exchanges a Sonos refresh token for a new access token; rate-limited per IP via Netlify Blobs.
- `/api/transcribe` accepts short command audio and transcribes it through OpenAI when cloud transcription is enabled; enforces per-IP and global daily caps via Netlify Blobs.
- Legacy `/sonos` app URLs redirect to `/`.

## 5. iOS App Configuration

The app callback scheme is already registered in:

- [Info.plist](/Users/kevinthau/sonos-voice/SonosVoiceRemote/Support/Info.plist)

The real controller defaults are already set in:

- [RealSonosController.swift](/Users/kevinthau/sonos-voice/SonosVoiceRemote/Services/Sonos/RealSonosController.swift)

Defaults already baked into the app:

- Auth start URL: `https://sonos-voice.netlify.app/sonos/oauth/start`
- iOS callback URL: `sonosvoiceremote://oauth/callback`

Optional overrides if you need them:

- `SONOS_AUTH_START_URL`
- `SONOS_IOS_CALLBACK_URL`
- `SONOS_CONTROL_API_BASE_URL`
- `SONOS_HOUSEHOLD_ID`
- `SONOS_VOICE_TRANSCRIPTION_MODE=apple|openai|auto`
- `SONOS_OPENAI_TRANSCRIPTION_URL`
- `SONOS_OPENAI_TRANSCRIPTION_TOKEN`

## 6. Deploy Order

1. Deploy the Netlify site serving `sonos-voice.netlify.app`.
2. Verify `https://sonos-voice.netlify.app/` loads the app and `https://sonos-voice.netlify.app/sonos/oauth/start` returns a redirect.
3. Save the Sonos integration key with the redirect URI and event callback URL above.
4. Build and run the iPhone app.
5. Tap `Sign In` in the Sonos controller card.
6. Complete Sonos login in the browser.
7. Confirm the browser redirects back to `sonosvoiceremote://oauth/callback`.
8. Confirm the app shows a connected Sonos household and discovered rooms.

## 7. Quick Validation

Validate Netlify routes:

```bash
curl -I https://sonos-voice.netlify.app/
curl -I https://sonos-voice.netlify.app/sonos/oauth/start
curl -i https://sonos-voice.netlify.app/sonos/events
```

Expected:

- `/` should return `200`.
- `/sonos/oauth/start` should return `302`.
- `/sonos/events` should return `200`.

## 8. Troubleshooting

If Sonos rejects the redirect URI:

- Confirm Sonos portal uses exactly `https://sonos-voice.netlify.app/sonos/oauth/callback`
- Confirm Netlify deploy is live on the same domain

If the app never comes back from the browser:

- Confirm the app has the `sonosvoiceremote` URL scheme in [Info.plist](/Users/kevinthau/sonos-voice/SonosVoiceRemote/Support/Info.plist)
- Confirm `SONOS_IOS_CALLBACK_URL=sonosvoiceremote://oauth/callback` in Netlify

If token exchange fails:

- Confirm `SONOS_CLIENT_ID` and `SONOS_CLIENT_SECRET` match the Sonos integration key
- Confirm the redirect URI in Netlify exactly matches the redirect URI in Sonos

If the app signs in but cannot control speakers:

- Confirm Sonos granted the requested control scope
- Confirm the selected household actually contains players

## 9. Production Follow-Up

This repo uses Netlify Functions as a lightweight OAuth broker. That is acceptable for a private friends-and-family launch. Possible next hardening steps:

- Persist tokens server-side per user (e.g. Supabase or Netlify Blobs) instead of relying on `localStorage` / Keychain.
- Add Sentry (or another error-reporting backend) for production crash visibility on both web and iOS.
- Add a Content-Security-Policy header on the SPA to reduce the XSS surface around localStorage-stored Sonos tokens.
- Port the JS intent parser tests from `SonosVoiceRemoteTests/IntentParserTests.swift` to Vitest so both clients stay in sync.

## 10. Pre-share Checklist

Before sharing the URL or TestFlight build with a new user:

- [ ] `SONOS_CLIENT_ID`, `SONOS_CLIENT_SECRET`, `SONOS_STATE_SECRET` are all set in Netlify.
- [ ] `SONOS_ALLOWED_HOUSEHOLDS` contains the new user's household ID.
- [ ] `OPENAI_API_KEY` and `SONOS_OPENAI_TRANSCRIPTION_TOKEN` are set if OpenAI transcription is enabled.
- [ ] `TRANSCRIBE_GLOBAL_DAILY_CAP` is set to a value matching your budget.
- [ ] `/privacy` loads in a browser and is reachable from the footer link on `/`.
- [ ] iOS app has up-to-date `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` strings (App Store / TestFlight require these).
