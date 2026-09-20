# Sayso reimagined — September 2026

The app is now a personal writing workspace, with warm paper reading surfaces, forest-teal controls, a native serif introduction, and matching Home, History, Modes, and Settings. The [current design system](../design-system/sayso/MASTER.md) records the chosen direction and how UI/UX Pro Max recommendations were adapted to iPhone.

## What changed

- Home explains the voice-to-text flow and opens the latest saved thought directly. The first-use guidance gives way to recent writing when history exists.
- Recording uses a focused reading sheet with duration, actual input level, listening state, and explicit finish/discard controls. Fixed controls adapt to landscape and large text.
- Results group the writing, mode/date context, copy/share/edit, and original/rewrite actions. Switching versions resets copy feedback and updates the displayed word count. Successful edits show the edited version.
- History groups saved thoughts by day, supports search and confirmed deletion, and opens an editable reading page. Rewrites continue updating the same stored entry while preserving its original.
- Modes separates untouched transcription, built-in rewrites, and personal instructions. Settings groups speech, vocabulary, rewriting, storage, and shortcuts.
- At accessibility text sizes, writing, saved rows, and prompt inputs appear before supplementary guidance and metadata. The result and recent-detail journeys assert that the writing is immediately visible.
- Both native icon assets and the raster fallback use the new palette while retaining Sayso's seven-bar voice mark.

The redesign preserves the in-app recording scope. It does not restore the removed keyboard, Live Activity, cross-app microphone behavior, or audio-file import. Speech providers, storage schemas, and rewrite prompts are unchanged.

## Evidence

The small-phone matrix is complete across a full UI run and subsequent focused reruns, including real dark appearance. Across those runs, all 27 unique UI methods have a passing outcome. This is combined evidence from successive source revisions, not a single green full-suite run of the latest revision. The larger-phone portrait journey also passed after a test-only numerical-tolerance fix. The [verification manifest](verification/reimagined-2026-09-20.json) records build/source provenance, result bundles, and screenshots.

| Check | Current evidence |
| --- | --- |
| Integrated build | `.build/reimagine/FinalGeometryBuild.xcresult`: successful final `build-for-testing`, Xcode 27.0 (`27A266a`), arm64 iOS 27 Simulator. The structured result reports zero errors and zero warnings; the preceding `FinalVerificationBuild` log separately notes skipped AppIntents metadata extraction because there is no AppIntents.framework dependency. The final build changes only the UI test geometry tolerance; app source is unchanged. |
| Unit tests | `.build/reimagine/SmallSmoke.xcresult`: 121 passed, one physical-iPhone-only speech probe skipped, zero unit failures. |
| Full small-phone UI run | Finalized `.build/reimagine/SmallLight.xcresult`: 23 passed, four failed, zero skipped. Portrait and landscape recording journeys passed. The four failures were investigated using recorded frames and UI hierarchies, corrected, and passed in later focused runs; this original bundle retains its failed status. |
| Focused light rerun | Finalized `.build/reimagine/SmallFocused.xcresult`: four passed, one failed, zero skipped. The largest-text saved-history flow, complete largest-text journey, landscape coverage, and named-mode History rewrite passed. The remaining prompt-editor failure was a full-frame containment assumption for a scrollable native text editor; its corrected test passed in `SmallDark`. |
| Dark appearance | Finalized `.build/reimagine/SmallDark.xcresult`: all six passed, zero failures or skips. Includes both `DesignLanguageUITests`, all three `ReimaginedAppUITests` journeys (portrait, landscape, largest text), and the existing dark recording-control test. The standard `scripts/verify.sh` now includes both redesign suites in its dark run. |
| Recording and persistence | Passing journeys cover recording, Copy feedback, edit/save/cancel, relaunch, recent thought → Done → Home, View all → History → Done, original/refined switching, rewrite, and one updated saved History entry. Largest-text tests also require writing to be immediately visible in the result and recent detail. |
| Motion | All five `MotionUITests` passed in finalized `SmallLight`, including native system Reduce Motion and restoration of its prior setting. |
| Larger phone | Finalized `.build/reimagine/LargeLightFinal.xcresult`: the complete portrait journey passed, zero failures or skips. The initial `LargeLight` bundle retains a failure from XCTest reporting a 44-point edit-button width as `43.99999999999997`; a 0.000001-point tolerance corrected only that floating-point comparison. |
| Native screenshots | Retained captures include [light Home](screenshots/reimagined-2026-09-20/home-small-light.png), [largest-text result](screenshots/reimagined-2026-09-20/result-ax-light.png) and [History](screenshots/reimagined-2026-09-20/history-ax-light.png), plus dark [Home](screenshots/reimagined-2026-09-20/home-small-dark.png), [recording](screenshots/reimagined-2026-09-20/recording-small-dark.png), [result](screenshots/reimagined-2026-09-20/result-small-dark.png), [Modes](screenshots/reimagined-2026-09-20/modes-small-dark.png), [saved detail](screenshots/reimagined-2026-09-20/history-detail-small-dark.png), [Settings](screenshots/reimagined-2026-09-20/settings-ax-dark.png), and [prompt editing](screenshots/reimagined-2026-09-20/prompt-editor-ax-dark.png). Larger-phone light [Home](screenshots/reimagined-2026-09-20/home-large-light.png), [result](screenshots/reimagined-2026-09-20/result-large-light.png), and [History detail](screenshots/reimagined-2026-09-20/history-detail-large-light.png) complete the retained set. All 13 native captures were visually inspected; no unresolved layout defect was found. |
| Contrast | Opaque semantic text pairs exceed 4.5:1 in both appearances. Lowest: secondary ink on accent-soft, 4.81:1 light / 6.03:1 dark. Primary-button labels: 7.62:1 / 7.74:1. These calculations do not establish every system-material contrast. |
| Source hygiene | Swift syntax parsing, verification-script syntax, and `git diff --check` passed. |

The first portrait run found that an outer Button frame did not expand the accessible `View all` target. Moving the minimum 44×44 frame into its explicit label corrected it; complete portrait, landscape, and largest-text reruns passed that target check. Subsequent AX review moved supplementary introductions and metadata after the relevant writing or input. Tests now scroll identified surfaces before querying lazy rows/editors, and scope History rows to the presented list so they cannot select the Home result underneath it. Native multiline editors require visibility and hittability rather than full-frame containment; custom controls retain their minimum target and containment assertions. The prompt test types a draft, cancels, and verifies the original saved prompt through Settings.

Early simulator attempts were cancelled before tests began. The successful small-device recovery exposed slow first-time framework indexing and graphics initialization; those early attempts are not passing evidence. After the first test failure, optional simulator diagnostics collection was interrupted only after all test callbacks completed. Xcode finalized the recorded result normally. Subsequent runs disable that optional collection and retain test screenshots and recordings.

The small device is an iPhone SE (3rd generation), 375-point width (`958368F5-0537-47CD-B6A4-6A93C7AAA7A9`). The larger verification device is an iPhone 18 Pro (`4289ACFC-68CE-4A42-9DD0-41CF430AC402`). Both use iOS 27.0 (`24A5423a`).

All speech fixtures are explicitly DEBUG-only scripted input. Passing tests establish UI/controller/storage behavior, not physical microphone transcription, model quality, Bluetooth recovery, haptics, or human VoiceOver/Voice Control usability. No release or App Store submission is part of this work.

## Verification boundary

The redesign and its simulator acceptance are complete. Physical microphone/model quality and human assistive-technology acceptance remain outside this simulator pass, as described above. The simulator appearance was restored after both the dark and larger-phone runs.

Reuse `.build/reimagine/DerivedData` with `test-without-building` only while app/test source hashes still match the verification manifest.
