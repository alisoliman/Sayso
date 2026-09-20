# Codebase simplification — 20 September 2026

This pass removes 341 net lines from production Swift and development scripts (103 and 238 respectively), measured against `045fa8f`. Features, persistence formats, prompts, colors, typography, spacing, icons, and motion settings are preserved.

## Changes

- Dictation takes a complete `WritingStyle` snapshot instead of passing and storing its mode, prompt, and transformation mode separately. Removed unused parameters, aliases, and one-use configuration wrappers.
- Removed the writing-style store's unused reset operation. Restoring a built-in prompt still follows the existing editor's Save path, including validation and explicit confirmation.
- Both speech providers share the same audio meter. Model installation validates at commit; the provider validates when resolving its cache identity. Runtime loading reuses the vocabulary parsed during validation. Cancellation, stale-session protection, background finalization, diagnostics, and failed-install recovery remain intact.
- Rewriting recognizes the source language once and builds each effective prompt once. System instructions are constant, list-comparison tokens are reused, and an unnecessary force unwrap is gone. Fidelity checks and retry policy are retained.
- Home and History share their Copy label. History groups filtered entries once instead of searching them again for every day. Language availability uses one optional collection instead of separate data/loading state.
- Removed `scripts/configure_tests.py`, an unreferenced generator duplicating the checked-in Xcode targets and shared scheme. The project remains directly editable and its source folders remain synchronized.

## Verification

Xcode 27.0 (`27A266a`), arm64 iOS 27.0 simulators: iPhone SE (3rd generation), device `958368F5-0537-47CD-B6A4-6A93C7AAA7A9`, and iPhone 18 Pro, device `4289ACFC-68CE-4A42-9DD0-41CF430AC402`.

| Check | Result |
| --- | --- |
| Simulator build for testing | Passed: `.build/simplification/Build.xcresult`. |
| Complete unit suite | 122 passed, one expected physical-device probe skipped, zero failures: `.build/simplification/UnitTests.xcresult`. Includes stereo/interleaved audio-meter regression coverage. |
| Prompt parity | All 576 before/after comparisons passed byte for byte. Reproducible harness and results: `.build/simplification/intelligence-prompt-parity/check.py` and `result.json`. |
| Light UI, small phone | Nine tests passed: portrait, landscape, largest-text recording/edit/relaunch/history journeys; cancellation/restart; real system Reduce Motion; Home/Settings/empty History; and all three writing-mode editor tests. `.build/simplification/UILight.xcresult`. |
| Dark UI, larger phone | Two tests passed: complete recording/edit/relaunch/history/rewrite journey and Home controls. `.build/simplification/UIDark.xcresult`. Real simulator appearance was set to dark and restored afterward. |
| Visual review | Inspected light Home, result, History, largest-text result, settled landscape result, and dark result/Copy feedback/saved detail. No visual regression found. Captures and name manifests are in `.build/simplification/screenshots-light/` and `screenshots-dark/`. |
| iPhone Release build | Passed: `.build/simplification/Release.xcresult`. The app is arm64/iOS 27; Start Dictation remains in generated App Intents metadata. No extensions, background-audio capability, Live Activity flag, or DEBUG fixture markers. |
| Swift syntax, verification-script syntax, preflight, diff whitespace | Passed. |

The UI runs comprise 11 executions of 10 distinct test methods. Both simulators were restored to their original light appearance, normal text size, and shutdown state; the Reduce Motion test verified restoration of that setting. Source hashes are retained in `.build/simplification/source-manifest.json`.

All `.build/` paths are local generated evidence excluded from Git. Simulator speech is scripted; this pass does not establish physical microphone recognition, Bluetooth recovery, model inference quality, haptics, or human assistive-technology acceptance. The existing test helper's deprecated `AnalyzerInput.buffer` warning remains; it was not introduced by these changes.
