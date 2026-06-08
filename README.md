# Sonos Voice Remote

An iOS-only SwiftUI voice remote for controlling Sonos rooms and starting Spotify playback.

## Project Shape

- `SonosVoiceRemote.xcodeproj` contains the app and test targets.
- `SonosVoiceRemote/` contains SwiftUI features, domain models, and service integrations.
- `SonosVoiceRemoteTests/` contains XCTest coverage for parsing, coordinators, Sonos, Spotify, and OpenAI transcription flows.

The previous React/Vite web app, Netlify functions, Node tests, and deployment scripts have been removed.

## Required Configuration

Configure these values through local Xcode build settings or an untracked `.xcconfig`:

- `SONOS_AUTH_BROKER_BASE_URL`: HTTPS base URL for the external Sonos auth broker.
- `SPOTIFY_CLIENT_ID`: Spotify app client ID.
- `SPOTIFY_REDIRECT_URL`: Spotify callback URL, for example `sonosvoiceremote://auth/spotify`.

The app stores user-provided OpenAI API keys in iOS Keychain. Sonos and Spotify OAuth tokens are also stored in Keychain.

## Verify

```sh
xcodebuild build -project SonosVoiceRemote.xcodeproj -scheme SonosVoiceRemote -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project SonosVoiceRemote.xcodeproj -scheme SonosVoiceRemote -destination 'platform=iOS Simulator,name=iPhone 17'
```
