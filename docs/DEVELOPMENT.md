# Development

## Requirements

- Xcode 27 or later
- An iOS 27 simulator or an iPhone running iOS 27
- macOS 27 for the optional Mac tools below

The Xcode project is checked in and edited directly. New Swift files added to `Sayso/`, `SaysoTests/` or `SaysoUITests/` are picked up automatically.

## Code overview

| Path | What's there |
| --- | --- |
| `Sayso/Views/` | Screens: Home, History, Modes and Settings |
| `Sayso/Models/` | Dictation state, saved history and writing modes |
| `Sayso/Services/SpeechService.swift` | Live transcription with Apple Speech |
| `Sayso/Services/Parakeet*.swift` | Parakeet download, storage and transcription |
| `Sayso/Services/IntelligenceService.swift` | Rewriting with Apple Intelligence |
| `Sayso/Services/DictationIntent.swift` | The "Start Dictation" shortcut |
| `Sayso/PreviewSupport/` | Fake speech input for previews and UI tests (debug builds only) |

## Running tests

In Xcode, press **⌘U**. From the command line:

```sh
xcodebuild test -project Sayso.xcodeproj -scheme Sayso \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Replace `iPhone 17` with any iOS 27 simulator you have. `xcrun simctl list devices available` lists them.

UI tests use scripted speech instead of the microphone. They check screens, navigation and saving, but not real recognition quality.

### Full check

`scripts/verify.sh` runs everything: unit tests and UI tests in light mode, the dark-mode UI tests, and a Release build.

```sh
export SAYSO_SIMULATOR_ID='<simulator UUID>'
./scripts/verify.sh
```

Use a dedicated simulator set to English. The script changes its appearance and text size (and puts them back afterwards) and resets its microphone permission. Logs and results go to `.build/`.

Run `./scripts/verify.sh --preflight-only` to check your Xcode and simulator setup without building anything.

If Xcode 27 isn't your default, point `DEVELOPER_DIR` at it first:

```sh
export DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer'
```

### Real speech on an iPhone

One test runs real speech recognition. It only runs on a physical iPhone, and only when `SAYSO_RUN_DEVICE_SPEECH_PROBE=1` is set in the test scheme's environment.

## Mac tools

These scripts compile parts of the app for macOS and run them against the real on-device models. They need macOS 27.

| Script | What it does |
| --- | --- |
| `scripts/verify_speech_helpers.sh` | Quick checks of audio conversion and transcript handling. No model download needed. |
| `scripts/evaluate-intelligence.sh` | Runs sample dictations through each writing mode and saves the results as JSON. |
| `scripts/evaluate-pipeline.sh --output report.json` | Generates spoken audio, transcribes it, then rewrites it. Tests speech and writing together. |

`evaluate-intelligence.sh` options:

- `--suite fixed|holdout|all` picks the built-in sample set.
- `--fixtures scripts/fixtures/<file>.json` uses one of the extra sample sets instead.
- `--case <id>` runs a single sample.
- `--repeat <n>` runs each sample several times.
- `--output <path>` sets where results are saved. The default is `/tmp/sayso-intelligence-evaluation.json`.

The model's output varies between runs, so read the results yourself rather than treating them as pass or fail. The `*-criteria.md` files in `scripts/fixtures/` describe what a good result looks like for each sample set.

## App icon

The icon is `Sayso/AppIcon.icon`, made in Apple's Icon Composer. A flat PNG fallback is generated with:

```sh
swift scripts/create_icon.swift Sayso/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

## Testing on a real iPhone

Simulators can't check everything. Before a release, try these on a device:

- **Permissions:** deny microphone access, then grant it from Settings. Recording should recover.
- **Offline:** once language files or Parakeet are downloaded, turn on Airplane Mode. Recording and rewriting should still work.
- **Without Apple Intelligence:** Original mode should still work. A failed rewrite should keep the original text.
- **Interruptions:** take a call, disconnect headphones, switch apps or lock the phone mid-recording. The recording should stop and keep the captured text.
- **History:** edit an entry, relaunch, rewrite it, and delete it. Turn history off and check new dictations aren't saved.
- **Shortcut:** run Start Dictation from Siri, Shortcuts and the Action button. It should start recording exactly once.
- **Accessibility:** try dark mode, the largest text sizes, VoiceOver and Reduce Motion.
- **Writing quality:** dictate names, numbers, dates, corrections ("no, I mean Tuesday") and mixed languages. Check each mode keeps the details right.
- **Performance:** check how quickly recording starts, how long text takes to appear after stopping, and battery use and heat during long recordings.
