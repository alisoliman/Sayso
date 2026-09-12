# Sayso design language

> Historical context: the Sayso keyboard and its cross-app recording/Live Activity support were removed on 12 September 2026. References and screenshots of those features below describe earlier revisions. See the [README](../README.md) for current behavior.

Design direction established 9 September 2026. Sayso turns a spoken thought into useful writing with a calm, precise interface. The ambition is an experience worthy of Apple Design Award consideration in 2028. Selection belongs to Apple; 2028 eligibility, categories and judging expectations must be checked when published. Apple's current awards recognize innovation, ingenuity and technical achievement, with categories including Interaction and Inclusivity. Those are useful quality lenses for this product, not a prediction of a future award. [Apple Design Awards](https://developer.apple.com/design/awards/)

## Principles

1. **Let the words lead.** Give the transcript room, clear reading order and an immediately useful next action. Keep controls close to the writing they affect. Empty states explain how to begin without presenting an empty dashboard.
2. **Make capture unmistakable.** At standard portrait text sizes, Home's full-width primary action reads **Start dictation**, **New dictation** or **Finish dictation** to match the current state. Accessibility sizes shorten the visible labels to **Dictate** and **Stop**. Compact layouts retain the symbol control with its complete accessibility label. Recording shows elapsed duration and a separate Discard action; the keyboard and Live Activity use the concise **Stop** label. The keyboard's processing instruction explicitly says the microphone is off. Success makes the text available for review and deliberate insertion.
3. **Use one expressive signature.** Home's seven-bar voice emblem gives Sayso a recognizable silhouette; the existing native seven-capsule app icon is retained. The live waveform represents current capture; decorative motion must never imply that an idle microphone is listening. Small system surfaces use familiar SF Symbols and essential status.
4. **Spend attention carefully.** Native typography, generous spacing and a restrained accent establish hierarchy. Glass belongs to native controls that benefit from separation; text rests on a stable, opaque surface. Shadows are subtle and functional.
5. **Design for the complete journey.** Recording, interruption, recovery, editing, History, Shortcuts, the keyboard and Live Activity form one product. The current platform boundary between app capture and explicit keyboard insertion stays visible in the instructions.
6. **Treat accessibility as product quality.** Preserve meaningful labels, readable text, direct actions and usable layouts as text grows. Status must remain understandable without color or animation. Apple recommends comfortable control size and spacing, with a default iOS control size of 44 points. [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)

## Visual grammar

| Role | Light | Dark | Use |
| --- | --- | --- | --- |
| Canvas | `#F8F6F2` | `#141218` | Warm porcelain / near-black plum |
| Surface | `#F0EDF3` | `#211D27` | Quiet grouping when needed |
| Ink | `#261F2F` | `#F5F0FA` | Primary reading and controls |
| Secondary ink | `#6D6674` | `#B8AEBD` | Supporting instructions and metadata |
| Accent | `#503968` | `#CEB8F2` | Aubergine / lavender; primary action and identity |
| On accent | `#FFFFFF` | `#261F2F` | Legible filled-button content |
| Hairline | `#DCD5E0` | `#49404F` | Decorative separation |

At accessibility text sizes and in compact landscape, introductory supporting copy and the duplicate provider shortcut yield space to essential actions; provider configuration remains in Settings. The large idle emblem also hides at accessibility sizes, while the small header mark remains. Source-defined Voice Control input labels match the current action title and retain Start/Stop recording aliases; hands-on Voice Control operation remains a validation gate.

Use the system typeface and native text styles. Restrict custom tracking to short labels. Duration uses monospaced digits so ticking does not shift the layout. Titles establish one clear reading entry point; captions carry context, never the only instruction needed to operate a control.

Use an 8-point rhythm for ordinary content, 4-point steps for tight relationships, and comfortable outer margins. Capsule actions signal a clear next step. Small utility controls retain their native shape and familiar placement. The keyboard intentionally keeps its established 5-point key gaps, portrait and compact row heights, and safe-area geometry to protect typing and host-editor space.

The app, UIKit keyboard and SwiftUI activity compile in different targets. Their named palette tokens match explicitly. ActivityKit resolves foreground and background from the same SwiftUI color scheme to avoid host-appearance mismatches. The Dynamic Island always uses lavender with dark ink for prominent actions.

### Computed token contrast

These are calculations from the final opaque sRGB tokens using `(lighter luminance + 0.05) / (darker luminance + 0.05)`, rounded to two decimals. They are not runtime observations or an accessibility audit; rendered opacity, glass, pressed states and system-host behavior need their own inspection. Keyboard key colors are `#FFFFFF` / `#343039`; utility keys are `#E6E1E8` / `#25212B`.

| Foreground / background | Light | Dark |
| --- | --- | --- |
| Ink / canvas | 14.75:1 | 16.58:1 |
| Ink / surface | 13.73:1 | 14.75:1 |
| Secondary ink / canvas | 5.12:1 | 8.70:1 |
| Secondary ink / surface | 4.76:1 | 7.74:1 |
| Accent / canvas | 9.15:1 | 10.41:1 |
| Accent / surface | 8.52:1 | 9.26:1 |
| On accent / accent | 9.88:1 | 8.91:1 |
| Ink / keyboard key | 15.92:1 | 11.50:1 |
| Ink / keyboard utility key | 12.35:1 | 14.07:1 |
| Hairline / canvas | 1.33:1 | 1.89:1 |
| Hairline / surface | 1.24:1 | 1.68:1 |

The revised light secondary ink, `#6D6674`, exceeds 4.5:1 on both reading backgrounds. Hairlines are decorative and must not carry required status, text or control boundaries.

## System surfaces

The keyboard prioritizes the current preview, Stop or Insert, Discard when available, and ordinary typing. An active Shift key uses the same filled accent treatment as a selected app control. The recorder's numeric status uses stable-width digits. During transcription/refinement, the instruction says the microphone is off. No text is inserted automatically and the keyboard never starts recording or launches Sayso.

The Live Activity shows phase, duration and essential controls without a decorative symbol container. Stale state requests returning to Sayso and hides recording controls. In the narrow landscape Island, a status symbol replaces duration; elapsed time remains in the expanded activity and keyboard. Recording text and audio never appear on the Lock Screen. These choices follow Apple's guidance for concise, legible activity content, app-consistent appearance and protection of sensitive information. [Apple Live Activities guidance](https://developer.apple.com/design/human-interface-guidelines/live-activities)

Existing lifecycle and privacy contracts are defined in [Keyboard design](KEYBOARD_DESIGN.md) and [Live Activity design](LIVE_ACTIVITY_DESIGN.md). Their past test evidence is historical evidence for its recorded source, not proof of this design revision. This revision's evidence is tracked in [Design verification](DESIGN_VERIFICATION.md), alongside the broader [Verification](VERIFICATION.md) record.

## Roadmap toward 2028

| Gate | Work and evidence required |
| --- | --- |
| Coherent foundation | Complete the visual system across Home, processing, results, editing, History, onboarding and extensions. Capture light/dark, compact and large-text views from the actual built app. Review reading order, action prominence and clipping. |
| Inclusive operation | Complete the full journey with VoiceOver, Voice Control, Switch Control and large text. Inspect Increase Contrast, Reduce Motion and Reduce Transparency. Include participants who use these settings daily; document failures and fixes. Apple's widget guidance specifically calls for status labels that update with the visible state. [Accessible Live Activities](https://developer.apple.com/documentation/activitykit/adding-accessible-descriptions-to-widgets-and-live-activities) |
| Real-device trust | Record on a physical iPhone, switch apps, stop/discard from keyboard and authenticated Lock Screen, and inspect the resulting words. Exercise interruptions, locked data protection, disabled/dismissed activities, stale status, app termination and the ten-minute limit. Measure latency, memory, battery and thermal impact during real recognition. Simulator fixtures do not establish microphone or background-audio behavior. |
| Everyday usefulness | Observe people taking a thought through recording, review and insertion in their usual apps. Measure task success, time to useful text, avoidable corrections and recovery from interruption. Improve the largest observed friction before expanding feature count. |
| Language and reach | Validate supported recognition languages with representative speakers and real material. Review localized copy, plurals, long labels, right-to-left layout and keyboard limitations. Publish only capability claims demonstrated by that evidence. |
| Distinctive refinement | Tune the voice emblem, transitions and tactile feedback around state changes. Keep motion optional, respect system settings and ensure the visual signature improves recognition without delaying writing. |
| Submission readiness | Recheck Apple's then-current award information and platform guidance; finish App Store and privacy requirements, device regression coverage and an honest product demonstration. Keep evidence and unresolved limitations attached to the release candidate. |

The design is ready to advance when representative people can understand and complete the whole journey, recover their words after failure and operate it with their preferred accessibility settings. Award consideration is an ambition built on that evidence.
