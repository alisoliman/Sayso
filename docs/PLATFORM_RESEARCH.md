# Apple platform research for Sayso

> Historical context: the Sayso keyboard and its cross-app recording/Live Activity support were removed on 12 September 2026. References and screenshots of those features below describe earlier revisions. See the [README](../README.md) for current behavior.

**Historical research snapshot:** the original observations below were recorded on 7 September 2026 against Xcode 26.6 / SDK 26.5. The installed-toolchain table and migration recommendations describe that earlier state. Xcode 27 is now installed and production has migrated; use [iOS 27 migration](IOS27_MIGRATION.md) and [current verification](VERIFICATION.md) for present source/build status. The separately dated Dynamic Island addendum below records a newly verified iOS 27 API.

Verified 7 September 2026 against official Apple documentation, Apple staff guidance, and the installed SDK. This is an implementation boundary document, not a claim that physical-device testing has passed.

## What iOS 27 actually adds

iOS 27 is announced and available in beta. Apple's June 8 announcement describes a fall release; Apple's current developer page still links Xcode 27 beta and iOS 27 beta. Do not describe iOS 27 as unannounced, or claim a verified production release date. [Apple announcement](https://www.apple.com/newsroom/2026/06/apple-unveils-next-generation-of-apple-intelligence-siri-ai-and-more/), [iOS developer updates](https://developer.apple.com/ios/whats-new/).

The WWDC26 Foundation Models release includes a rebuilt on-device model, refined guardrails, image inputs, Private Cloud Compute access, a public model-provider abstraction, dynamic profiles, and an Evaluations framework. Our relevant subset is the improved local text model and better context accounting. Private Cloud Compute is server processing, so it is outside the current local-only product scope. Open-source model hosting is also deferred. The expanded framework does not require adding agents, image understanding, or multiple providers to a dictation app. [WWDC26 Foundation Models](https://developer.apple.com/videos/play/wwdc2026/241/).

The June 2026 Speech changes introduce `AssetInputSequenceProvider`, `CaptureInputSequenceProvider`, and `AnalyzerInputConverter` to simplify audio ingestion and conversion. These names are absent from the installed 26.5 Speech Swift interface. They are migration opportunities after the 27 SDK becomes available locally, not symbols to copy into the current build. [Speech updates](https://developer.apple.com/documentation/updates/speech).

## Historical local build and verification boundary

Observed with `xcodebuild -version`, `xcrun --sdk iphoneos --show-sdk-path`, `xcrun simctl list runtimes`, and `sw_vers`:

| Component | Installed in the 7 September snapshot |
| --- | --- |
| Xcode | 26.6, build 17F113 |
| iPhoneOS SDK | 26.5 |
| Latest installed iOS Simulator runtime | 26.5, build 23F77 |
| Host macOS | 26.6.2, build 25G83 |

Build the native foundation using APIs present in this SDK. Keep iOS 27 as the product target and perform a separate Xcode 27 build and iOS 27 simulator/device validation once that toolchain is installed. Running a 26.5 simulator does not verify iOS 27 behavior. An app built with existing `SystemLanguageModel` APIs is expected to use the OS-provided model on a newer OS, but that forward-runtime behavior and output quality must be checked on the actual 27 device.

## iOS 27 Dynamic Island width — 8 September addendum

Apple's WWDC26 *Live Activities essentials* explains that compact/minimal Dynamic Island presentations are available in landscape, where the view cannot expand horizontally as it does in portrait. Its limited-width example reads `EnvironmentValues.isDynamicIslandLimitedInWidth` and substitutes a progress symbol for the trailing timer. This is a documented layout adaptation, rather than a reason to force a portrait timer width into the landscape pill. [WWDC26 session, limited-width example at 10:33](https://developer.apple.com/videos/play/wwdc2026/223/).

Apple's property reference applies the value to `compactLeading`, `compactTrailing` and `minimal`. The installed Xcode 27 beta 6 WidgetKit interface also declares it available from iOS 27.0. [API reference](https://developer.apple.com/documentation/swiftui/environmentvalues/isdynamicislandlimitedinwidth).

Sayso's adaptive trailing view uses a status symbol when width is limited and retains duration in the keyboard and expanded/Lock Screen activity. This follows a reproduced native timer-clipping finding; it does not itself establish visual success. [The original finding](../.build/ios27-compact-boundary-visual-review.json) and [interrupted verification record](../.build/ios27-final-verification-pause.json) are retained. Adaptive Island/keyboard retests and a fresh full sequence remain pending in [Verification](VERIFICATION.md).

## Speech: use SpeechAnalyzer and SpeechTranscriber

`SpeechTranscriber` is Apple's current general-purpose speech-to-text module for `SpeechAnalyzer`, suitable for normal conversation. Check `SpeechTranscriber.isAvailable` and use `supportedLocale(equivalentTo:)` / `supportedLocales` before creation. `installedLocales` differs from downloadable supported locales. Do not derive capability from an iPhone model name or assume every OS locale is supported. Apple documents `DictationTranscriber` as a possible alternative when the newer transcriber is unavailable; a latest-device product can instead give a precise unavailable state. [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber), [hardware availability](https://developer.apple.com/documentation/speech/speechtranscriber/isavailable).

The analyzer accepts asynchronous audio inputs and supplies asynchronous results. For the installed SDK use `AVAudioEngine` capture, obtain the analyzer's preferred format, convert with `AVAudioConverter`, and supply `AnalyzerInput` values. Keep stable finalized text separate from replaceable volatile text, and finish analysis after stopping capture so that final words are retained. Apple's WWDC sample demonstrates this architecture. [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [WWDC25 speech session](https://developer.apple.com/videos/play/wwdc2025/277/).

Speech assets are system-managed downloads shared across apps. Use `AssetInventory.assetInstallationRequest(supporting:)`, then `downloadAndInstall()` when a request is returned. An installed asset yields no installation request. Surface preparation/download state before recording, and support retry after network or storage failure. Reservations are limited, so use `maximumReservedLocales` instead of a hard-coded count, and release unused reservations when the selected language changes. The current API is `reserve(locale:)` / `release(reservedLocale:)`; the older WWDC25 transcript contains obsolete allocation names. [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory), [installation request](https://developer.apple.com/documentation/speech/assetinventory/assetinstallationrequest(supporting:)), [reservation limit](https://developer.apple.com/documentation/speech/assetinventory/maximumreservedlocales).

Request microphone permission at the person's first recording action and include `NSMicrophoneUsageDescription`. Apple's current speech authorization guide explicitly scopes `SFSpeechRecognizer.requestAuthorization` and its server-recognition permission to `SFSpeechRecognizer`; analyzer transcriber modules do not send voice audio to Apple's servers. Do not add a cloud speech fallback silently. Local inference still may require an initial asset download. [Speech permission guide](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition).

## Apple Intelligence: optional text refinement, with the original always available

Use `SystemLanguageModel.default` and a short-lived `LanguageModelSession` for polishing, concise rewriting, and bullet formatting. Refining and editing supplied text are documented model capabilities. Before use, inspect availability and explain the real reason when unavailable: ineligible device, Apple Intelligence disabled, or model not ready. Model downloads can take time. Dictation and the original transcript should remain useful independently. [Generating content and performing tasks](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models).

Speech locale support and Foundation Models language support are independent. Check `supportsLocale(_:)` before refinement, set the person's locale in instructions, preserve the spoken language, and handle unsupported-language errors. Do not advertise an unverified fixed language count. [Foundation Models language support](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models).

The installed SDK includes `contextSize` and the iOS 26.4 `tokenCount(for:)` overloads for prompts, instructions, schemas, tools, and transcript entries. Budget both input and output instead of assuming a universal 4,096-token window. Never send an arbitrarily long dictation to a single session. Preserve raw text on refusals, context overflow, cancellation, and generation failure. These are application design recommendations; prompt wording alone does not guarantee factual fidelity. Evaluate names, amounts, dates, negations, spoken corrections, lists, and multilingual text on actual models.

## Simulator is useful but is not the iPhone model

Apple staff explain that Foundation Models in iOS Simulator calls the host Mac's models. The Mac needs Apple Intelligence enabled and downloaded; matching host/runtime versions matters because model assets can differ. A successful UI run is not evidence that the iPhone's local model, speech assets, microphone path, haptics, or thermal behavior works. Apple staff also document that Apple Intelligence does not work in a macOS VM. [Apple staff simulator guidance](https://developer.apple.com/forums/thread/787445).

Use deterministic preview/test data for visual and state-machine tests, explicitly separated from real recording. Probe real speech and model availability at runtime. No authoritative blanket claim that SpeechTranscriber works in every simulator configuration was established in this research; report the actual observed runtime capability instead.

## Cross-app access and keyboard constraints

A third-party keyboard runs in its own isolated process. Apple's keyboard documentation says extensions cannot directly access the text-input view; the extension guide states custom keyboards have no microphone access. Full access does not establish a supported general-purpose microphone entitlement. Therefore, a keyboard target alone must not promise systemwide voice capture. The implemented keyboard inserts results explicitly produced and shared by the containing app. An explicit ongoing-recording variant uses a foreground start, background audio for the already-active capture, and ID-scoped Stop/Discard commands. Physical audio behavior and actual host-field insertion require their own validation; see KEYBOARD_DESIGN.md. [Creating a keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard), [keyboard extension limits](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html), [open-access restrictions](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard).

Open the app to start capture; offer Copy, Share, finished-result keyboard handoff, and the explicit ongoing-recording flow. An App Intent with `supportedModes = .foreground(.immediate)` is a documented way to bring the app forward before an action runs, appropriate for a recording shortcut. App Intents expose app actions to system surfaces; they are not a grant to read or edit arbitrary other apps. Route the action into the existing recording state machine and permission flow. [AppIntent supported modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes-5zhmb).

## Native visual direction

SwiftUI's native glass APIs already support interactive controls and morphing shapes: `glassEffect`, `GlassEffectContainer`, `glassEffectID`, and glass button styles. Use them for the small control layer and keep transcript content readable. Limit simultaneous glass effects and group related effects in containers for rendering performance. Recording, processing, and finished states can share a stable central geometry. Respect Reduce Motion and use meaningful state transitions rather than continuous decorative movement. The accessibility and restraint choices are product recommendations grounded in the native API's behavior. [Applying Liquid Glass](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views).

## Required evidence before declaring the goal complete

1. Build the app and run real UI flows on the installed simulator; record which OS was tested.
2. Verify permission denial, absent assets, download failure, unavailable Intelligence, empty recordings, interruptions, cancellation, and long text without losing the original.
3. Run a fixed transcription/refinement evaluation corpus; do not call mocked outputs speech or model verification.
4. Build with Xcode 27 and repeat on iOS 27 Simulator when available.
5. On the user's iPhone 17 Pro with iOS 27, test actual microphone capture, model availability, offline operation after downloads, latency, repeated recordings, interruptions, audio routes, haptics, and accessibility. Capture the exact OS/build and model behavior.

Only completed checks should be reported as passed. Outstanding device or toolchain checks remain explicit release gates.
