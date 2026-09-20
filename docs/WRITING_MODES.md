# Custom rewrite prompts and modes

Open **Modes** from Home. Tap **Edit prompt** beneath a rewrite mode, or **Add mode** to save a name and prompt together. The same editors are available in **Settings → Writing modes** and through **Edit prompts & modes** in the Rewrite menus.

Changes are drafts until Save. Cancel or dismiss the editor to discard them. Built-in rewrite modes offer **Restore default prompt**, which also requires Save. Named modes can be renamed or deleted; deleting the selected mode switches the next recording to Original. Names must be unique, and both a name and prompt are required.

The saved library is shared by new recordings, Home rewrites and History rewrites. Existing Custom instructions migrate automatically. Original remains an exact transcription mode. Editing an Email or Notes prompt uses the custom rewrite path so the original mode’s fixed layout cannot override the new instructions. Restoring its default prompt restores the original processing path.

Each operation captures its mode and prompt when it starts. Saved results retain that name and prompt even if the mode is later renamed or deleted. Existing history without this metadata continues to load. Rewrite failures or cancellation retain the prior result, and selecting Original restores its archival transcript.

## Verification — 8 September 2026

- Xcode 27 beta 6 (`27A5252f`) built the app, extensions and test targets for iOS 27 Simulator successfully. The unsigned iPhone Release build also passed.
- **15 host XCTest tests passed, with zero failures:** eight `WritingStyleStoreTests` and seven `DictationStoreTests`. These ran the actual production model/store source and existing tests in a temporary macOS Swift package, with the unchanged `WritingMode` enum extracted from `IntelligenceService.swift`. They verify storage, migration, validation, routing selection and backward-compatible history; they do not execute the iOS controller, UI or Apple Intelligence.
- Additional controller tests and three native `WritingModesUITests` compile. Simulator runs were interrupted before any test case executed after startup stalled. A shared simulator was also being used by another development task; a separate simulator then stalled while the host ran critically low on disk space. No native UI pass or visual acceptance is claimed. The separate simulator and temporary build caches were cleaned up.
- Local generated logs (excluded from Git) are `.build/writing-modes-build.log`, `.build/writing-modes-release.log`, `.build/writing-modes-host-tests.log`, and the `writing-modes-tests`, `writing-modes-retry` and `writing-modes-isolated` logs/result bundles.

To run the iOS checks when the simulator is available, use the Xcode 27 toolchain and a separate simulator as described in the [build instructions](../README.md#build-and-run):

```sh
xcodebuild test -project Sayso.xcodeproj -scheme Sayso \
  -destination "platform=iOS Simulator,id=$SAYSO_SIMULATOR_ID" \
  -parallel-testing-enabled NO -jobs 2 \
  -only-testing:SaysoTests \
  -only-testing:SaysoUITests/WritingModesUITests \
  -only-testing:SaysoUITests/SaysoUITests/testCustomModeCommitsOnlyValidDoneAndSwipeDismissPreservesSavedStyle \
  -only-testing:SaysoUITests/SaysoUITests/testHomeModesSettingsAndEmptyHistoryAreReachable \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```
