# Xcode Cloud Internal TestFlight Workflow

This repo is prepared for Xcode Cloud with a shared scheme, automatic signing settings, a valid bundle version, and an app icon asset catalog. Xcode Cloud workflow definitions live in App Store Connect, not in this repository.

## Project Values

- Project: `SonosVoiceRemote.xcodeproj`
- Scheme: `SonosVoiceRemote`
- App target: `SonosVoiceRemote`
- Test target: `SonosVoiceRemoteTests`
- Bundle ID: `com.kevinthau.SonosVoiceRemote`
- Team ID: `3JXY2MS2Y3`
- Version: `1.0`
- Build number: `$(CURRENT_PROJECT_VERSION)`
- Signing: Automatic
- Repository: `https://github.com/Kevinmthau/Sonos-voice.git`
- Branch: `main`

## CLI Sanity Check

Run the repository check before creating or starting a cloud build:

```sh
./scripts/xcode-cloud-check.sh
```

The script uses `xcodebuild` from the command line, writes derived data to the ignored `.derived/` directory, disables local code signing, and also runs the web tests/build.

To also validate the Release archive action locally without provisioning:

```sh
RUN_ARCHIVE_CHECK=1 ./scripts/xcode-cloud-check.sh
```

## Create The Workflow Without Local Xcode

Use App Store Connect in a browser, or the App Store Connect API. There is no `xcodebuild` command that creates Xcode Cloud workflows.

Recommended App Store Connect workflow values:

| Setting | Value |
| --- | --- |
| Name | `Internal TestFlight` |
| Product | `SonosVoiceRemote` |
| Project | `SonosVoiceRemote.xcodeproj` |
| Scheme | `SonosVoiceRemote` |
| Branch | `main` |
| Start condition | Manual starts, plus changes to `main` if desired |
| Environment | Latest stable Xcode available in Xcode Cloud |
| Test action | Scheme `SonosVoiceRemote`, configuration `Debug`, latest available iPhone simulator |
| Archive action | Scheme `SonosVoiceRemote`, configuration `Release`, platform `iOS` |
| Distribution | `TestFlight (Internal Testing Only)` |

## Start A Cloud Build From The CLI

Create an App Store Connect API key with access to Xcode Cloud, then export these values locally:

```sh
export ASC_KEY_ID="KEYID12345"
export ASC_ISSUER_ID="00000000-0000-0000-0000-000000000000"
export ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_KEYID12345.p8"
export ASC_WORKFLOW_ID="00000000-0000-0000-0000-000000000000"
```

Start the configured workflow:

```sh
./scripts/xcode-cloud-start-build.sh
```

To find the workflow ID through the API:

```sh
curl -sS -H "Authorization: Bearer $ASC_JWT" \
  "https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=com.kevinthau.SonosVoiceRemote"

curl -sS -H "Authorization: Bearer $ASC_JWT" \
  "https://api.appstoreconnect.apple.com/v1/apps/$APP_ID/ciProduct"

curl -sS -H "Authorization: Bearer $ASC_JWT" \
  "https://api.appstoreconnect.apple.com/v1/ciProducts/$CI_PRODUCT_ID/relationships/workflows"
```

`scripts/xcode-cloud-start-build.sh` generates its own short-lived JWT from `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_PATH`, so `ASC_JWT` is only needed if you are making manual API calls.

## Internal Testers

After a successful Xcode Cloud archive, open the app in App Store Connect and go to TestFlight > Internal Testing. Create an internal group, invite App Store Connect users, then add the Xcode Cloud build to the group.

Apple notes that Xcode Cloud builds may still need to be manually added to internal groups in App Store Connect, even when the group has automatic distribution enabled.

## Notes

- This project does not need Xcode Cloud custom build scripts right now because it has no CocoaPods, Carthage, Swift Package, or other native dependency install step.
- Xcode Cloud manages cloud build numbers. If App Store Connect reports a duplicate build number, set the next Xcode Cloud build number in App Store Connect or bump `CURRENT_PROJECT_VERSION` before starting the next archive.
- The app embeds the Sonos OAuth start URL and client ID through build settings. Do not put Sonos client secrets, access tokens, or refresh tokens in Xcode Cloud environment variables for a TestFlight app.
- Export-compliance is declared in `SonosVoiceRemote/Support/Info.plist` via `ITSAppUsesNonExemptEncryption = false`, so every Xcode Cloud archive uploads to TestFlight without prompting for an encryption questionnaire. If the app ever adds non-exempt encryption (custom crypto beyond Apple's HTTPS/Keychain APIs), flip that key and supply the matching compliance docs.

## References

- [Xcode Cloud](https://developer.apple.com/documentation/xcode/xcode-cloud)
- [Configuring your first Xcode Cloud workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow/)
- [Create a workflow](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-ciworkflows)
- [Start a build](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-cibuildruns)
- [Read the Xcode Cloud product for an app](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-ciproduct)
- [List all Xcode Cloud products](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-ciproducts)
- [Setting the next build number for Xcode Cloud builds](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds/)
