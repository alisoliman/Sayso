# Sayso — a place for spoken thoughts

This is the current product-wide direction for the September 2026 reimagining. It supersedes the visual direction in the historical `docs/DESIGN_LANGUAGE.md`; the original voice-to-text, privacy, and text-preservation contracts remain.

## Product and journey

Sayso is an iPhone writing tool. Speak in the app, review the captured words, optionally rewrite them, and copy or share the result. A returning person can open their latest saved thought from Home or search all their writing in History. Original words remain available after rewriting. No account or onboarding gate is needed.

1. Home: a clear editorial introduction, a compact explanation for first use, the latest saved thought when available, mode selection, and one primary recording action.
2. Recording: a focused reading sheet, real input meter, duration, visible listening/finishing state, Stop, and confirmed discard. Keep the app open while speaking.
3. Result: a paper-like reading surface, mode/date context, original/refined switching, copy confirmation, edit, Share, and Rewrite. Processing stays cancellable.
4. History: grouped saved pages, search, recoverable navigation, and explicit delete confirmation.
5. Modes: original transcription, built-in rewrites, and personal instructions, with separate selection and editing controls.
6. Settings: speech setup, language, writing preferences, vocabulary, storage, and honest privacy information.

## Research and application

The ui-ux-pro-max query `productivity note taking minimal --design-system` returned Flat Design and a teal/orange note-taking palette. These are relevant to the native writing tool. Its marketing-page pattern and web font import are not applied. The earlier broader query returned scroll storytelling, which was rejected as unsuitable. The SwiftUI stack search supported native navigation and meaningful accessibility labels.

The design below is a deliberate native adaptation, not unedited generated output. Apple’s [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [typography](https://developer.apple.com/design/human-interface-guidelines/typography), and [motion](https://developer.apple.com/design/human-interface-guidelines/motion) guidance informs scalable type, restrained motion, and readable layouts.

## Semantic palette

| Token | Light | Dark | Purpose |
| --- | --- | --- | --- |
| canvas | #F5F3EC | #121C19 | Warm background |
| paper | #FFFEF9 | #1B2823 | Writing and grouped content |
| surface | #EAECE4 | #24312C | Secondary controls |
| accentSoft | #E0EEE5 | #263E33 | Selected mode, quiet accent fields |
| accent | #155E52 | #9DDAC6 | Actions and selection |
| onAccent | #FFFFFF | #103C33 | Filled action labels |
| ink | #20352D | #F0F4ED | Reading text |
| secondaryInk | #5C6961 | #B0BFB5 | Supporting text |
| hairline | #D4DBD1 | #46594E | Decorative separation |
| recording | #A33E27 | #FFB49B | Active recording indicator, also named in text |

## Type, spacing, and controls

- Use native system fonts and SF Symbols. Editorial serif is limited to introductory headings; writing uses native sans type for extended reading.
- All reading sizes scale with Dynamic Type. Supporting text uses semantic styles. Do not cap accessibility sizes.
- Use 24-point phone gutters, 16/24/28-point group spacing, and a bounded reading width on wider screens.
- Opaque reading surfaces with 24–28-point corners; primary action and mode control use 20-point corners. Avoid ornamental shadows and large gradients.
- Touch targets are at least 44 points. Icon controls have accessible labels. Selection uses a checkmark as well as color.
- Portrait keeps the recording action within thumb reach. Landscape uses a compact control row. Large text moves secondary detail into scrollable content and wraps actions.
- At accessibility sizes, put writing and editing inputs before decorative introductions and metadata. Keep context after the primary actions, and use scrolling without shrinking the user's text.
- Motion is tied to state changes, not decorative loops. Reduce Motion removes spatial transitions and meter movement. Controls act immediately.

## Verification scope

Build the native app and run actual simulator journeys; inspect screenshots for light/dark, small portrait/landscape, and largest Dynamic Type. Exercise capture lifecycle with the existing scripted fixture, original preservation, edit/save, history, mode editing, Settings, cancellation, and actual system Reduce Motion. This demonstrates UI and storage behavior, not microphone recognition or model quality. Physical speech and assistive-technology acceptance must be reported separately.
