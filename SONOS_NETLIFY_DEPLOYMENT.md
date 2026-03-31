# Sonos + Netlify Deployment Checklist

This document wires the `SonosVoiceRemote` app to `sonos-voice.netlify.app` using Netlify Functions as the Sonos OAuth broker.

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

- `SONOS_CLIENT_ID`
- `SONOS_CLIENT_SECRET`
- `SONOS_STATE_SECRET`
- `SONOS_REDIRECT_URI=https://sonos-voice.netlify.app/sonos/oauth/callback`
- `SONOS_IOS_CALLBACK_URL=sonosvoiceremote://oauth/callback`

Recommended:

- Generate `SONOS_STATE_SECRET` as a long random string, at least 32 bytes of entropy.
- Do not expose `SONOS_CLIENT_SECRET` in client-side code.
- This repo already bakes in your current Sonos client ID as a default, but keeping `SONOS_CLIENT_ID` set in Netlify is still cleaner and easier to rotate later.

## 4. Netlify Routing

After deploy, these routes should exist:

- `https://sonos-voice.netlify.app/sonos/oauth/start`
- `https://sonos-voice.netlify.app/sonos/oauth/callback`
- `https://sonos-voice.netlify.app/sonos/events`

Expected behavior:

- `/sonos/oauth/start` redirects to Sonos login.
- `/sonos/oauth/callback` exchanges the Sonos auth code for tokens and redirects into the iPhone app.
- `/sonos/events` returns `200 OK` and can later be expanded to verify/store Sonos events.

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

## 6. Deploy Order

1. Deploy the Netlify site serving `sonos-voice.netlify.app`.
2. Verify `https://sonos-voice.netlify.app/sonos/oauth/start` returns a redirect.
3. Save the Sonos integration key with the redirect URI and event callback URL above.
4. Build and run the iPhone app.
5. Tap `Sign In` in the Sonos controller card.
6. Complete Sonos login in the browser.
7. Confirm the browser redirects back to `sonosvoiceremote://oauth/callback`.
8. Confirm the app shows a connected Sonos household and discovered rooms.

## 7. Quick Validation

Validate Netlify routes:

```bash
curl -I https://sonos-voice.netlify.app/sonos/oauth/start
curl -i https://sonos-voice.netlify.app/sonos/events
```

Expected:

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

This repo uses Netlify Functions as a lightweight OAuth broker. That is acceptable for initial deployment, but the next hardening step is:

- Persist tokens server-side per user instead of round-tripping them through the iOS callback query string.
