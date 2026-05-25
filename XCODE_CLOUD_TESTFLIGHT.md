# Xcode Cloud Internal TestFlight Workflow

Xcode Cloud workflow definitions are stored in Xcode/App Store Connect, not in a repo file. This repo is prepared for the workflow with a shared scheme, automatic signing settings, a valid bundle version, and an app icon asset catalog.

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

## Create The Workflow

1. Open `SonosVoiceRemote.xcodeproj` in Xcode.
2. Choose Product > Xcode Cloud > Create Workflow.
3. Select the `SonosVoiceRemote` app and connect this Git repository if Xcode asks.
4. If App Store Connect does not already have an app record, create one with bundle ID `com.kevinthau.SonosVoiceRemote`.
5. Configure the workflow:

| Setting | Value |
| --- | --- |
| Name | `Internal TestFlight` |
| Branch | `main` |
| Start condition | On changes to `main`, plus manual starts |
| Environment | Latest stable Xcode available in Xcode Cloud |
| Test action | Scheme `SonosVoiceRemote`, configuration `Debug`, latest available iPhone simulator |
| Archive action | Scheme `SonosVoiceRemote`, configuration `Release`, platform `iOS` |
| Distribution | `TestFlight (Internal Testing Only)` |

## Internal Testers

After a successful Xcode Cloud archive, open the app in App Store Connect and go to TestFlight > Internal Testing. Create an internal group, invite App Store Connect users, then add the Xcode Cloud build to the group.

Apple notes that Xcode Cloud builds must be manually added to internal groups in App Store Connect, even when the group has automatic distribution enabled.

## Notes

- This project does not need Xcode Cloud custom build scripts right now because it has no CocoaPods, Carthage, or other external native dependency install step.
- Xcode Cloud assigns build numbers to cloud builds. If App Store Connect reports a duplicate build number, set the next Xcode Cloud build number in App Store Connect or bump `CURRENT_PROJECT_VERSION` before starting the next archive.
- The app embeds the Sonos OAuth start URL and client ID through build settings. Do not put Sonos client secrets, access tokens, or refresh tokens in Xcode Cloud environment variables for a TestFlight app.

## References

- [Getting started with Xcode Cloud](https://developer.apple.com/documentation/xcode/getting-started-with-xcode-cloud)
- [Creating a workflow that builds your app for distribution](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution)
- [Add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)
- [Writing custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)
- [Setting the next build number for Xcode Cloud builds](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds)
