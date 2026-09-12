# Design revision — 9 September 2026

> Historical context: the Sayso keyboard and its cross-app recording/Live Activity support were removed on 12 September 2026. References and screenshots of those features below describe earlier revisions. See the [README](../README.md) for current behavior.

This revision implements the [Sayso design language](DESIGN_LANGUAGE.md): warm porcelain and plum surfaces, a seven-bar voice signature, a labeled primary recording action, consistent reading typography, and coordinated History, Modes, Settings, keyboard and Live Activity controls.

This document preserves the visual-design cohort and its source snapshots. The subsequent [motion pass](MOTION_DESIGN.md) records the later implementation and observed system Reduce Motion behavior, including changes during an active recording.

## Scope and evidence

The production changes are presentation and interaction refinements. Recording providers, persistence formats, App Group identities, explicit keyboard insertion and Live Activity freshness rules retain their existing contracts. The existing native seven-capsule app icon remains in place.

The build uses Xcode 27.0 beta 6 (`27A5252f`), the iOS 27 simulator SDK, and a dedicated iPhone 17 Pro simulator (`5950F29E-BEA9-4314-9B76-0698897B9395`). Build and test evidence lives under `.build/` and is intentionally not committed. Selected native screenshots and the final evidence summary accompany this document.

The UI suite uses isolated DEBUG-only saved-text and scripted-speech fixtures. Its checks exercise native navigation, text preservation, edit/copy/share/import, recording lifecycle presentation and explicit keyboard insertion. They do not establish microphone recognition or Apple Intelligence output quality.

## Accessibility decisions

- Body and supporting text use Dynamic Type. Expressive serif type is limited to introductory headings; live and saved writing use matching native sans typography.
- Portrait primary actions have visible labels and matching Voice Control input labels; compact landscape uses a familiar microphone/stop symbol with explicit accessibility names. At accessibility text sizes the visible actions shorten to Dictate and Stop, and redundant introductory copy/provider controls give essential actions more room. Existing Start/Stop recording accessibility names remain available.
- Explicit Home and History utility frames reserve at least 44 points; native system control hit areas remain system-managed. Original and Rewrite labels own their full hit areas.
- Larger text switches action groups to vertical layouts, and screens remain scrollable. Compact landscape uses its own control layout.
- A static identity emblem does not imply active capture. The waveform, symbol changes, scrolling and button motion respect Reduce Motion in source.
- Content and primary controls are opaque. System glass provides separation for navigation, the compact utility tray and a few utility actions such as Latest words. It follows system accessibility preferences.
- Computed opaque text/background contrast is recorded in the design language. It is not a measurement of every rendered system material or visual state.

## What the review caught

Native captures revealed a large-text primary label extending outside its filled button even though the control itself was reachable. The primary style now preserves its label’s intrinsic height, and accessibility-size recording actions use concise Dictate/Stop labels. Portrait and landscape prioritize the essential controls when space is limited.

The landscape test measured only 176 points of reading space in the first revision. Removing the duplicate provider shortcut from the compact tray restores room for the transcript without hiding Settings. The prompt-edit control also received an explicit rectangular hit area and additional room after a measured target was only 42 points wide.

At maximum text size, Settings' native picker truncated the selected speech-provider name even after moving it below the row label. Accessibility layouts now use a wrapping menu label around the same native selection options. The normal-size picker stays compact.

New test harness failures were retained and corrected: native toolbar visual frames do not describe their entire system-managed hit areas; native Forms lazily load offscreen rows; a presented sheet leaves hidden Home elements in the accessibility hierarchy; edge-origin swipes can trigger the system Home gesture; and preview text must be saved before testing History. The final checks use explicit containers, central gestures, real Edit/Save and unchanged assertions about preserving the original words.

Intermediate result bundles remain in `.build/Design-Final-Light.xcresult` and `.build/Design-Light-Fixes.xcresult`. Interrupted iterations are not counted as completed suites. A test passing does not replace inspecting its rendered screenshots: the picker truncation was visible despite passing reachability checks.

## Final validation

The final simulator **build-for-testing passed**, including the app, keyboard, Live Activity and UI-test targets. **All 14 distinct selected UI methods have passing latest results.** Validation ran in the following cohorts; this is not a claim that the entire repository suite ran on one build.

| Local result bundle in `.build/` | Passed / executed | Scope |
| --- | --- | --- |
| `Design-Validated-Light.xcresult` | 11 / 12 | Recording, editing, saved words, landscape and native keyboard insertion; retained the 42-point prompt-edit target failure |
| `Design-Targets-Light.xcresult` | 2 / 2 | Corrected target and normal secondary-screen navigation |
| `Design-Dark.xcresult` | 4 / 4 | Dark Home, largest-text secondary screens and saved writing, native Live Activity Stop |
| `Design-Settings-Light.xcresult` | 2 / 2 | Intermediate stacked picker; screenshot review still caught truncated text |
| `Design-Settings-Dark.xcresult` | 1 / 1 | Same intermediate picker in dark mode |
| `Design-Wrapping-Settings-Light.xcresult` | 2 / 2 | Final wrapping values, actual provider/language selection, persistence and normal Settings navigation |
| `Design-Wrapping-Settings-Dark.xcresult` | 1 / 1 | Final wrapping values, selection and persistence in dark mode |

These cohorts contain 24 completed executions: 23 passed and one failed before its correction. The [evidence manifest](verification/design-2026-09-09.json) records every selected method, its latest outcome, the final Swift source hashes and screenshot provenance. Final Settings-only changes received focused reruns; unchanged journeys retain their preceding results. `git diff --check` also passed.

The functional checks cover recording and processing presentation, review/resume during a long transcript, refinement cancellation, discard recovery, copy/edit/history persistence, original-versus-rewrite preservation, native Share and import cancellation, portrait and both landscape orientations at standard and largest text sizes, explicit keyboard insertion into a native Settings field with Full Access off, and Stop from Notification Center's actual Live Activity. The latter uses scripted speech and verifies the expected resulting words.

## Native captures

All images are unmodified simulator screenshots exported from XCTest attachments. They show the actual app and extension views with fixture text where needed. The clock is normalized to 9:41 for comparison. Screenshot hashes and source attachments are recorded in the [evidence manifest](verification/design-2026-09-09.json).

| Surface | Captures |
| --- | --- |
| Home | [Light](screenshots/design-2026-09-09/home-light.png), [dark](screenshots/design-2026-09-09/home-dark.png) |
| Recording and result | [Recording](screenshots/design-2026-09-09/recording-light.png), [result](screenshots/design-2026-09-09/result-light.png) |
| Secondary screens | [Modes](screenshots/design-2026-09-09/modes-light.png), [Settings](screenshots/design-2026-09-09/settings-light.png) |
| Keyboard and activity | [Explicit native keyboard insertion](screenshots/design-2026-09-09/keyboard-light.png), [Live Activity controls](screenshots/design-2026-09-09/live-activity-dark.png) |
| Largest text | [Home light](screenshots/design-2026-09-09/home-accessibility.png), [Home dark](screenshots/design-2026-09-09/home-dark-accessibility.png), [Modes](screenshots/design-2026-09-09/modes-accessibility.png) |
| Largest text in Settings | [Light](screenshots/design-2026-09-09/settings-accessibility.png), [dark](screenshots/design-2026-09-09/settings-dark-accessibility.png) |
| Largest text language selection | [Light](screenshots/design-2026-09-09/language-accessibility.png), [dark](screenshots/design-2026-09-09/language-dark-accessibility.png) |
| Largest text in History | [Empty](screenshots/design-2026-09-09/history-empty-accessibility.png), [saved actions in dark](screenshots/design-2026-09-09/history-dark-accessibility.png) |
| Compact landscape | [Standard text](screenshots/design-2026-09-09/home-landscape.png), [largest text](screenshots/design-2026-09-09/home-landscape-accessibility.png) |

## Remaining acceptance

Physical iPhone microphone recognition, Bluetooth and interruption recovery, background capture, haptics, latency, battery and thermal behavior still need device acceptance. VoiceOver reading order and announcements, Voice Control operation, Switch Control and Reduce Transparency behavior need hands-on validation. Reduce Motion has subsequent simulator evidence in the motion pass; physical-device accessibility validation remains open. Full localization and right-to-left journeys remain roadmap work.

Apple selects its award recipients. This revision establishes a coherent implemented design foundation; it does not establish eligibility for, or guarantee, an Apple Design Award in 2028. The roadmap names the evidence needed to pursue that ambition.
