# Sayso

A quiet native iPhone app for turning speech into useful text. Record, choose a writing style, and copy, share or insert the result where you need it. Sayso supports local Parakeet transcription through FluidAudio, Apple Speech, and optional Apple Intelligence rewriting. No Sayso account, API key or server is required.

**iOS 27.0 or later · SwiftUI · Parakeet / Apple Speech · Foundation Models**

[Current normal-launch Home](docs/screenshots/ios27/final-visual/home-light-normal-final.png)

## What it does

- **Apple Speech**, the default, provides live transcription with a waveform, timer and explicit Start, Stop and Discard controls. Long transcripts follow the newest words; scrolling back lets you review without losing your place.
- **Parakeet TDT v3** is an optional local speech model in Settings. Download it once (about 500 MB) or import its Core ML model folder. It detects 25 European languages, including English and Dutch, automatically and transcribes after Stop. Parakeet recordings and imports are limited to ten minutes.
- **Original**, the default, keeps your words. **Clean, Message, Email, Notes and Custom** optionally refine them with Apple Intelligence. The original remains available when rewriting is cancelled or fails.
- Customize the rewrite prompt for Clean, Message, Email, Notes or Custom, and add named modes with their own instructions. Open **Modes** and tap the pencil or **Add mode**, or go to **Settings → Writing modes**. Saved modes are available for recording, imports and rewrites from Home or History. Built-in prompts can be restored; your existing Custom instructions migrate automatically. [Writing modes and verification](docs/WRITING_MODES.md).
- Editable results, original/refined comparison, local searchable history, vocabulary spellings and a choice of supported speech languages. Saving history is optional.
- Copy, native Share and audio-file import. The embedded keyboard supports ordinary typing and explicit insertion of a result sent from Sayso.
- **Dictate in another app** starts recording in Sayso and provides a Live Activity, Dynamic Island and Stop/Discard controls while you return to your destination. Recording is limited to ten minutes.
- Shortcuts for ordinary and keyboard dictation, suitable for Siri or the Action button.
- Native Liquid Glass controls and a layered app icon, light/dark appearances, compact landscape layouts, Dynamic Type, VoiceOver labels and Reduce Motion support.

Language/model downloads need internet access initially; Parakeet is fetched only through the explicit download control. A missing local model never silently switches providers. Apple Intelligence must be available for rewriting; **Original works with Parakeet without Apple Intelligence**. Rewrites can still omit or change meaning, so keep the original available and review important details. [Parakeet setup, supported files and verification](docs/PARAKEET.md).

## Build and run

Open `Sayso.xcodeproj` in **Xcode 27 or later**, select the **Sayso** scheme, then choose an iOS 27 simulator or connected iPhone. For command-line builds, point `DEVELOPER_DIR` at your chosen Xcode 27 installation and select one of your own simulator UUIDs:

```sh
# Change this example path to your Xcode 27 installation.
export DEVELOPER_DIR='/Applications/Xcode-beta.app/Contents/Developer'
xcodebuild -version
xcrun simctl list devices available

export SAYSO_SIMULATOR_ID='<your dedicated iOS 27 simulator UUID>'
export SAYSO_REQUIRED_IOS_MAJOR=27

xcodebuild -project Sayso.xcodeproj -scheme Sayso \
  -destination "platform=iOS Simulator,id=$SAYSO_SIMULATOR_ID" \
  -derivedDataPath .build/ios27 build CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-

./scripts/verify.sh --preflight-only
./scripts/verify.sh
```

`DEVELOPER_DIR` selects the toolchain without changing global `xcode-select`. Xcode 27's simulator interface is its bundled `Contents/Applications/DeviceHub.app`.

Preflight records toolchain, runtime and source provenance without changing simulator settings or building. The full script builds and runs the app and extension checks; use a dedicated simulator with English system labels and its software keyboard visible. Set `SAYSO_SIMULATOR_ID` explicitly because the script's default UUID belongs to the original development machine.

For a physical iPhone, choose **your Apple Developer signing team** in Signing & Capabilities for the app, keyboard and Live Activity extension. The checked-in identifiers use `solimanali.Sayso` and App Group `group.solimanali.Sayso`; provision these for your team or replace the bundle identifiers and matching App Group entitlements together. The existing team setting is developer-specific.

## Use the keyboard

Enable Sayso through **Settings → General → Keyboard → Keyboards** using the in-app setup guide. For a finished result, select **Send to keyboard**, return to your destination, choose Sayso with the globe and tap **Insert**. Insertion works with Full Access off and never happens automatically.

For ongoing dictation, choose **Dictate in another app** or its Keyboard Dictation shortcut, then manually return to the destination. Stop through the Live Activity, or enable Full Access to use keyboard Stop/Discard. Insert the finished result explicitly. The keyboard does not launch Sayso or capture audio. Ordinary dictation finishes when Sayso goes into the background. [Keyboard behavior and platform boundaries](docs/KEYBOARD_DESIGN.md).

## Verification and iPhone acceptance

**Optional local Parakeet:** the device Release build and 35 focused model/capture tests passed. The broader run plus focused rerun has passing latest results for 145 distinct methods, with the existing physical-device probe skipped. Real Parakeet inference through Sayso’s audio converter also passed on the Mac with networking denied, including right-channel-only stereo audio. Apple Speech remains the default. [Setup, detailed results and iPhone acceptance boundary](docs/PARAKEET.md).

**Build 2 adds recording diagnostics.** Empty-input errors distinguish missing microphone buffers, failed conversion, audio not processed by the analyzer and audio with no recognized words. **Copy diagnostics** explicitly copies content-free counters and technical metadata to the local-device pasteboard. This is diagnostic instrumentation, not a confirmed recognition fix.

**36 focused simulator tests passed:** 19 controller, 7 diagnostic and 10 speech-pipeline tests. The final signed iPhone build-for-testing and unsigned Release both passed; all three Release bundles are arm64/iOS 27 with no DEBUG fixture markers. No phone was installed or launched, and the opt-in synthetic-file device probe **has not run**. [Build 2 verification report](docs/verification/recording-diagnostics-build-2.json), [detailed status](docs/VERIFICATION.md#build-2-recording-diagnostics--8-september).

**Historical build 1** has passing latest results for **122 distinct methods: 101 unit and 21 UI**. Its composed sequence records 134 executions: 131 passes and three retained failures resolved by test-only fixes. Its unsigned Release passed. Those results predate build 2 and do not certify the changed diagnostics source. [Historical results and retained failures](docs/VERIFICATION.md#historical-build-1-composed-verification--8-september), [iOS 27 migration](docs/IOS27_MIGRATION.md).

The remaining acceptance boundaries are explicit:

- **Physical iPhone:** the user reported no detected speech with both internal input and AirPods, then suspected Mac screen sharing and requested a retry. The cause is unconfirmed. Successful real microphone recognition, continued background capture, offline asset readiness, Bluetooth/interruptions, haptics, battery, thermal behavior and latency remain acceptance work on the intended iPhone 17 Pro running iOS 27. Follow the [device acceptance checklist](docs/DEVICE_ACCEPTANCE.md).
- **Writing quality:** real iOS 27 model quality is unverified. Historical macOS 26.x evaluations contain known Notes ownership, segmentation and correction failures; their separate cohorts are not an iOS 27 accuracy claim. This host is macOS 26.6.2, and current model runners require macOS 27. [Writing evaluations](docs/INTELLIGENCE_EVALUATION.md), [Notes challenge](docs/NOTES_CHALLENGE_EVALUATION.md), [structured Notes comparison](docs/STRUCTURED_NOTES_EVALUATION.md).
- **Runtime:** simulator boot and app tests work, but native runtime signature verification still reports `-67054` and AMFI cache-signature diagnostics remain unresolved. Passing app tests do not certify runtime integrity. [Environment and diagnostics](docs/IOS27_MIGRATION.md).
- **Presentation:** 25 consecutive AX portrait timer captures retained their leading zero; persistent clipping was not reproduced. The earlier isolated frame remains qualified in the record. Native captures cover the recorded layouts and four icon styles. Dense samples of a historical interaction video show brief transition text/status overlap; current-source motion and real-device performance remain unverified. [Visual evidence](docs/VERIFICATION.md), [icon design](docs/ICON_DESIGN.md).

## Data and development

Sayso does not send audio or text to a server or persist microphone recordings. History uses protected local files and may be included in device backups. Only a deliberately shared result reaches the keyboard's App Group; it expires from insertion after ten minutes and can be cleared in Sayso. The keyboard does not collect surrounding host-field text. Copy uses the local-device pasteboard. Recording diagnostics contain counts, durations, levels, format/port-type identifiers and app/OS metadata; they contain no audio, transcript, vocabulary, input-device names or route identifiers.

Production code is in `Sayso/`; the keyboard is in `SaysoKeyboard/`, the Live Activity in `SaysoRecordingActivity/`, and shared transfer types in `Shared/` and `RecordingActivityShared/`. Unit and UI checks live in `SaysoTests/` and `SaysoUITests/`.

DEBUG-only preview and scripted speech fixtures isolate test data. Their captures verify presentation and lifecycle, not recognition, real background audio or model quality. The verification record retains source hashes and the boundary for every reported result. [Apple API research](docs/PLATFORM_RESEARCH.md), [speech validation](docs/SPEECH_VALIDATION.md), [Live Activity design](docs/LIVE_ACTIVITY_DESIGN.md).

Source, documentation and selected screenshots are included in Git. Links into `.build/` in the detailed verification records refer to **local generated evidence excluded from Git**, including logs, result bundles and inspection reports; they are not downloadable repository artifacts. Run the documented checks to generate evidence for your own environment.
