# Motion design

> Historical context: the Sayso keyboard and its cross-app recording/Live Activity support were removed on 12 September 2026. References and screenshots of those features below describe earlier revisions. See the [README](../README.md) for current behavior.

Sayso uses motion to acknowledge a press, explain a state change, or reveal newly available text. The reading surface stays quiet. This document describes the implementation and simulator evidence from 9 September 2026.

## Motion grammar

The app shares three timing definitions in `SaysoTheme.swift`: `feedback` is a 160 ms ease-out, `stateChange` is a 260 ms ease-in-out, and `settle` is a spring with a 0.30 response and 0.88 damping fraction. The spring response is a tuning parameter, not a promise of an exact completion time. Native symbol replacement effects retain their system-defined interpolation.

| Intent | Trigger and behavior | Timing | Reduce Motion |
| --- | --- | --- | --- |
| Acknowledge a press | Primary, quiet, and plain actions dim and scale to 0.985 while pressed. Primary opacity is 0.82, quiet 0.65, and plain 0.68. | 160 ms; primary release uses `settle`. | Opacity changes immediately; scale stays at 1 and custom timing is removed. |
| Explain a new reading surface | Home changes between idle, live dictation, and result. Outgoing content clears before incoming content fades in from an 8 pt vertical offset. Finishing/refining do not independently replace the current reading surface; the displayed content determines the transition. | Outgoing: 90 ms. Incoming: 220 ms after a 100 ms presentation delay. Surrounding layout: 260 ms. | Identity transition and no custom animation. |
| Keep controls connected to the task | Home's portrait and compact control layouts settle when the dictation phase changes. | `settle` spring | Immediate layout change. |
| Confirm a changed action or mode | Home's microphone/stop symbol and writing-mode symbol use native replacement; their text fades. Listening/Finishing and Refining/Ready labels fade on phase changes. | 160 ms wrapper | Identity content changes. |
| Confirm a mode selection | Modes fades its selected fill, outline, and checkmark. Selection, edit, and Add mode controls use plain press feedback. | 160 ms | Selection updates immediately. Dismissal is never delayed. |
| Confirm copying | Home and History replace the copy symbol with a checkmark and fade Copy/Copied. A hidden sizing label reserves the confirmation footprint so adjacent controls stay put. | 160 ms wrapper | Immediate label and symbol change. |
| Compare the original and refined text | The words and their layout update together, immediately. Press feedback and a label fade acknowledge the toggle. | Toggle label: 160 ms. Paragraph: no animation. | Immediate text and label replacement. |
| Reflect actual microphone input | A 43-bar shape interpolates its energy from the measured input level. Silence and Stop settle to a line; there is no clock-driven waveform. | 160 ms ease-out while recording; 220 ms when stopping. | A stationary line; transcript and status continue updating. |
| Follow new words without losing the reading position | Home scrolls to the latest transcript only while follow mode is active. Manual scrolling pauses following. Latest words fades into view and explicitly returns to the bottom. | Automatic follow: 160 ms. Explicit return: 250 ms smooth. Latest words visibility: 160 ms. | Immediate scrolling and visibility changes. |
| Reveal keyboard handoff progress | A changed session/phase, result identity, consumed state, empty state, or unavailable state reveals the updated preview, instruction, and insertion control from 0.65 opacity to 1. Initial appearance and unchanged polling do not animate. | 180 ms ease-out | No reveal. A live Reduce Motion notification removes active reveal animations. |
| Make Live Activity phase changes legible | The Lock Screen and expanded Dynamic Island phase title and symbol fade when their displayed value changes. Compact/minimal symbols and elapsed time use identity transitions. | 180 ms ease-out | No custom fade. Reduced luminance and stale status also disable it. |

## Interaction invariants

- Recording, Stop, Cancel, copying, mode selection, and keyboard insertion execute directly from their actions. No operation waits for an animation completion or a delayed dismissal. The existing two-second Copy confirmation reset changes presentation only.
- Partial recognition and result text explicitly clear their animation transactions. New words and recognition corrections do not drift, stagger, or animate character by character. Switching versions updates paragraph height and actions together; outgoing lines cannot fade over newly positioned controls.
- The live reading layout clears inherited animation. The meter uses a geometry group around its drawing area so a wrapped transcript line and the meter below it move together; only its inner bars interpolate. Automatic following animates the surrounding scroll position. The status keeps its own local animation.
- Reading-surface replacement stages only presentation. It does not delay microphone capture, Stop, Cancel or result availability. The previous surface fades out before the next becomes legible, so different paragraphs do not occupy the same reading space.
- Copy confirmation reserves layout space. Motion does not create a second accessible sizing label or replace existing action identifiers.
- Keyboard content and enabled states are updated before its opacity reveal. The reveal does not retain an old recording snapshot, move typing keys, or animate typing and deletion. New changes can replace an in-progress reveal from its current presentation opacity; hiding the keyboard removes it.
- Keyboard one-second polling can update elapsed time without triggering a reveal: the visual-state comparison excludes elapsed seconds. There are no new polling loops for motion.
- Live Activity freshness updates do not retrigger phase animation. Timers retain their native ticking and freshness bound. Stale status appears immediately, and Stop disappears without a lingering animated target after recording ends. Intent buttons retain native feedback.
- SwiftUI motion reads the current Reduce Motion environment. The keyboard separately observes the system setting while visible. Live Activities also respond to reduced luminance. Native sheets, navigation, menus, glass controls, and progress indicators retain system behavior.
- The idle voice emblem is static. Decorative loops, perpetual pulsing, and whole-screen motion are absent from the custom motion grammar.

## Implementation map

- [Shared timing, press styles, and input meter](../Sayso/Views/SaysoTheme.swift)
- [Home state changes, transcript following, and result actions](../Sayso/ContentView.swift)
- [History comparison and copy confirmation](../Sayso/Views/HistoryView.swift)
- [Mode selection and press feedback](../Sayso/Views/ModePickerView.swift)
- [Keyboard handoff reveal and live Reduce Motion observer](../SaysoKeyboard/KeyboardViewController.swift)
- [Live Activity phase content and identity transitions](../SaysoRecordingActivity/SaysoRecordingActivity.swift)

The meter boundary follows Apple's [geometryGroup documentation](https://developer.apple.com/documentation/swiftui/view/geometrygroup()), which explains how ancestor layout changes otherwise reach animated drawing views.

The platform references are Apple's [Motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion) and [Animating data updates in widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities). The timings and behaviors above are derived from Sayso's source, not claimed as timings prescribed by Apple.

## Runtime verification

The motion pass uses a dedicated iPhone 17 Pro simulator running iOS 27 (24A5423a), built with Xcode 27 beta 6 (27A5252f). Scripted speech exercises the real app controller and native UI; it does not measure microphone recognition or Apple Intelligence quality. Motion tests read the actual system preference and change it through Settings, with restoration in teardown.

Continuous simulator capture and native XCTest recordings exposed three layout problems that static screenshots missed: the idle emblem briefly remained behind new words, finishing and result paragraphs briefly shared a baseline, and a growing landscape transcript crossed the moving meter. Reading-surface replacement now clears outgoing content first, while transcript reflow keeps the paragraph and meter together. Original/refined paragraph changes are immediate so their controls cannot move over fading old lines.

Copy tests assert that the control's width and leading edge remain stable during confirmation. Cancellation tests restart as soon as the real recording action becomes available and check that stale text and refinement state do not reappear. The live system-setting test resumes the same recording after off/on/off changes and verifies the exact final words.

The same active recording is preserved in the unmodified [standard](motion/2026-09-09/runtime-standard.png), [Reduce Motion](motion/2026-09-09/runtime-reduced.png), and [restored standard](motion/2026-09-09/runtime-restored.png) captures. The meter changes from a steady non-flat shape to a stationary line and back to the same shape. The [test timeline](motion/2026-09-09/runtime-setting-timeline.txt) records the actual native switch, system accessibility flag, same running app instance, and exact result. A steady microphone level is intentionally a steady shape in both modes. These unmodified captures come from `Motion-Final-Dark`; the live off/on/off flow also passes in the later `Motion-Meter` cohort.

The native keyboard check uses Full Access, sends Stop from the extension, foregrounds Sayso to let the audio-free fixture consume that command, then returns to the keyboard and verifies exact insertion plus its disabled Inserted state. It does not establish background microphone operation. Video review found no key-row movement or overlapping feedback. Native app switching obscures the continuous processing-to-ready transition.

The latest source builds successfully. Its final portrait and compact recording/copy checks both pass. Across the motion pass, all **10 distinct UI methods have a passing latest outcome**; the [evidence manifest](verification/motion-2026-09-09.json) records which source snapshot each cohort exercised. This is not a claim that every method ran after the final geometry-only change.

| Result bundle in `.build/` | Passed / total | Scope |
| --- | --- | --- |
| `Motion-Geometry.xcresult` | 2 / 2 | Latest geometry boundary; portrait and landscape recording, result and stable Copy feedback. |
| `Motion-Meter.xcresult` | 3 / 3 | Drawing wrapper; portrait, landscape and same-recording system off/on/off changes. |
| `Motion-Keyboard.xcresult` | 1 / 1 | Native keyboard Stop, exact insertion, consumed state and cleanup. |
| `Motion-Final-Dark.xcresult` | 6 / 7 | All six motion methods pass; the keyboard host cold-start failed before recording. |
| `Motion-Refined.xcresult` | 8 / 9 | Light motion, actual reduced-motion wrappers, largest text, History and Live Activity Stop; hidden keyboard setup failed. |
| `Motion-System.xcresult` | 0 / 3 | Initial Settings helper targeted a label wrapper; software keyboard was hidden. |
| `Motion-Standard.xcresult` | 4 / 5 | Initial normal motion and surrounding flows; hidden keyboard setup failed. |

The Settings helper was corrected to target the observed native switch. Simulator software-keyboard visibility was restored. The isolated keyboard rerun passed without application changes or a retry workaround. Earlier temporal defects and the intermediate clipped-meter dropout remain documented in the manifest; passing functional checks alone did not close them. The final [landscape frame sheet](motion/2026-09-09/landscape-wrapping-frames.png), cropped from the latest capture at 30 frames per second, shows the meter below each newly wrapped line with no observed overlap or dropout.

[Watch the 15-second recording and Copy demo](motion/2026-09-09/recording-and-copy.mp4). It is a cut from the final simulator recording at real speed, resized for sharing; it is not a generated animation.

### Scope of the evidence

Simulator captures establish observed UI behavior. They are not a physical-device frame-rate, power, thermal, microphone, or model-quality benchmark. Native recordings can have variable frame cadence; the earlier History comparison capture contains a 1.69-second gap between coherent before/after states, so it does not prove every intervening frame. The paragraph's explicit no-animation transaction is also checked in source.

The [earlier design screenshots](screenshots/design-2026-09-09/) and [design verification](DESIGN_VERIFICATION.md) predate the motion pass and remain static layout evidence. They are not presented as new animation verification.
