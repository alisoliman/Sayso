# Speech validation

**Historical validation snapshot:** this report describes the 7 September macOS 26.6.2 / SDK 26.5 runs and their original source. It is not a current iOS 27 report. Production now uses the iOS 27 native converter/audio tap; the current helper script requires macOS 27 and SDK 27 and refuses this macOS 26 host before execution. See [iOS 27 migration](IOS27_MIGRATION.md) and [current verification](VERIFICATION.md), including the ten passing native pipeline tests. The observations below are preserved without changing their platform or source claims.

Checked on 7 September 2026 with Xcode 26.6 and the installed iOS 26.5 SDK.

## Repeatable checks

At the recorded historical revision, `scripts/verify_speech_helpers.sh` compiled the then-production PCM converter and transcript accumulator with Swift 6 strict concurrency and ran on macOS 26 or later. It needs no microphone permission or speech model assets. The same core cases also have XCTest coverage in `SaysoTests/SpeechPipelineTests.swift`.

Observed passing checks:

- A microphone buffer copy owns its PCM data independently of the source buffer.
- 96,000 Float32 input frames at 48 kHz produce exactly 32,000 Int16 frames at 16 kHz, with contiguous sample timestamps. End-of-stream resampling padding is excluded from the captured timeline.
- Revised phrases replace their volatile drafts without duplicating preceding final phrases.
- Adjacent phrase boundaries preserve the final prefix.
- An empty replacement removes withdrawn text.
- Replacing a word with its own audio timestamp preserves surrounding words.

The service and controller also passed standalone strict-concurrency typechecks in both the project's Swift 5 mode and Swift 6 mode against the installed iOS simulator SDK. These checks establish compile compatibility; they do not run an iPhone microphone.

## Real recognition probe on the Mac

`scripts/probe_local_speech.sh` creates a temporary speech fixture with the installed macOS Samantha voice, then analyzes it using `SpeechAnalyzer`, `SpeechTranscriber` with the time-indexed progressive preset, and the production transcript accumulator. The script requires existing English speech assets and never calls an asset installation API. It releases only a locale reservation it acquired itself and removes its temporary audio afterward.

On this Mac, English appeared in `SpeechTranscriber.installedLocales`. `AssetInventory.status` reported `supported` before reserving the locale and `installed` afterward. The app reserves the locale before checking its assets for this reason.

The actual result was a **mismatch**, with one article substitution:

| Field | Result |
| --- | --- |
| Host | macOS 26.6.2, build 25G83 |
| Locale | `en_US` |
| Model downloads | None |
| Expected | Please send **the** meeting notes tomorrow morning. Keep the message clear and friendly. |
| Recognized | Please send **a** meeting notes tomorrow morning. Keep the message clear and friendly. |
| Results received | 18 total, including 2 final results |
| Analysis time | Approximately 0.89 seconds |

This confirms that real local file recognition, progressive updates, finalization, and transcript accumulation executed. It also demonstrates that the speech model can misrecognize a word. No correction was hard-coded. One synthetic fixture is not an accuracy benchmark, and this run does not validate iPhone hardware or an iOS simulator's speech model.

## iPhone checks still required

Test microphone capture on the intended physical iPhone, including initial language download, permission denial, silence, final words spoken just before Stop, long recordings, multilingual dictation, Bluetooth input and removal, incoming calls, lock/background transitions, and airplane mode after assets are installed. Ordinary dictation stops capturing when backgrounded, checkpoints already recognized words, and requests only temporary execution to finish the existing transcript. Explicit **Dictate in another app** continues an already-started recording with system controls and a ten-minute limit. Both device lifecycle behaviors require a real iPhone test.

Custom vocabulary is supplied to `AnalysisContext`; Apple's current documentation describes this feature specifically for `DictationTranscriber`. A recognition improvement from vocabulary hints with `SpeechTranscriber` has not been verified.

API references: [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [SpeechTranscriber results](https://developer.apple.com/documentation/speech/speechtranscriber/result), [locale reservations](https://developer.apple.com/documentation/speech/assetinventory/reserve(locale:)), and [contextual strings](https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings).
