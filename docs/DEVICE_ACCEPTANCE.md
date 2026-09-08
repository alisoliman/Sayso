# Physical-device acceptance

Run on an iPhone 17 Pro or Pro Max with iOS 27 after installing Xcode 27. Record OS build, app build, Siri/device language, and whether Apple Intelligence and speech language assets are ready. This is an unexecuted checklist, not a passing test report.

## First run and local operation

1. Launch without microphone permission. Recording requests it only after an explicit record/shortcut action. Deny, retry, use Open Settings, and grant; no blank screen or locked record control.
2. Select a supported speech language with assets not yet downloaded. Start; observe download progress. Cancel, interrupt connectivity, and retry. Unsupported languages give a useful error.
3. Record 15 seconds in Original mode. Check live text, final words, timer, waveform, and copy/share. Repeat ten times and switch modes/languages between recordings.
4. After downloads, enable Airplane Mode. Record and refine. Verify both work with no network and that no outbound audio/text path exists.
5. Disable Apple Intelligence or remove/unready its model. Dictation must remain usable and the original must survive a requested rewrite.

## Recovery and lifecycle

- Stop mid-sentence, pause before stop, and record silence. No duplicated or lost finalized segments.
- Cancel preparation; cancel an active recording with confirmation; cancel refinement. New recording remains usable.
- In ordinary dictation, receive a call, disconnect wired/Bluetooth audio, switch apps, and lock the phone. Recording should stop; captured text is preserved. Only the explicitly chosen cross-app flow should continue on app switch/lock.
- Import short M4A, WAV, and MP3 files; empty/corrupt audio should give a recoverable error. Cancel a long import.
- Background immediately after stopping. Verify history contains the captured original even when refinement cannot finish.
- Turn off history, dictate, and relaunch. New dictation is absent; previously stored entries stay until deleted.
- Edit a history entry, relaunch, and verify original and edited text. Rewrite it from History and from Home after a manual correction; the correction must remain. Original explicitly restores the archive. Test deletion and cancellation of deletion.

## Ongoing recording from another app

- Choose Dictate in another app or the Keyboard Dictation Action button shortcut. Verify recording starts only after Sayso is foreground and a Live Activity is visible. Disable Live Activities and verify capture is cancelled with useful instructions.
- Return to Notes/Messages and keep speaking. Verify all audio after the switch is transcribed. Stop from the keyboard with Full Access on, wait for writing, then explicitly Insert the exact final result. Repeat with Full Access off, stopping through the Live Activity instead.
- Stop and Discard from expanded Dynamic Island and Lock Screen after authentication. A Discard accepted just before writing completes must win; delayed commands must not affect the next recording.
- Wait through the ten-minute recording limit and through slow-writing/system background expiration. The microphone stops; available source words survive; no unfinished rewrite is shared.
- Discard while recording, finishing, or refining. Check no current-session provisional history or shared result returns after delayed cleanup. Earlier history remains intact.
- Dismiss the Live Activity, revoke permission, interrupt audio, lock/unlock, force-quit and relaunch. Verify no invisible capture, stale controls, or surprise restart. Check protected text becomes available again only under normal unlock rules.
- Interrupt audio during the initial Live Activity setup. Sayso must return to usable controls without displaying Listening for a stopped microphone. Kill the app during capture and verify its last activity becomes stale, its timer stops at the last confirmation window, and relaunch removes the abandoned activity.
- Repeat with history disabled, Bluetooth capture, Airplane Mode after model assets are ready, VoiceOver, and battery/thermal instrumentation.

## Writing quality

Run the fixed local-model corpus in the evaluation artifact and additional English/Dutch (or chosen-language) examples. Compare the original manually. Check names, numbers, money, times, negations, uncertainty, self-corrections, mixed languages, and quoted instructions. Test all modes. Deliberately exceed model context; no silent truncation or replacement with an empty result.

A successful generation is not a fidelity guarantee. New numeric forms are rejected, but omitted/reassigned details or spelled-out numbers can still need review.

## Interaction and integration

- Assign Start Dictation to the Action button through Shortcuts; cold/warm launches start exactly once after the app is foreground. Siri and sayso://record route into the same permission/lifecycle behavior.
- Copy into Notes and Messages; use native Share. Sayso does not send the message itself.
- Enable the Sayso keyboard with Full Access off. Send a result from Home and History, manually return to Notes/Messages, switch to Sayso, and explicitly Insert. Verify no insertion before tapping, exact Unicode at the current cursor/selection, no accidental double insertion, and re-sending an edited version of the same dictation works.
- Type letters, shift, numbers/symbols, space, return and repeated backspace; switch with the globe. Test secure fields and apps that reject third-party keyboards.
- Share with history disabled; only the explicit result should reach the keyboard. Replace it, expire it, clear it, delete its saved source, lock the phone, and relaunch Sayso. Verify expired copies are unreadable in the keyboard and purged when the host returns.
- Light/dark appearance, largest accessibility sizes, VoiceOver, Reduce Motion, Increase Contrast, and Reduce Transparency.
- Verify microphone/stop hit areas, text selection, mode-picker dismissal, sheets, keyboard editing, and long-history scrolling. During a long recording, newest words stay visible; scroll back and confirm recognition does not force you away; Latest words resumes following.
- Measure first and warm recording start, stop-to-original latency, stop-to-refinement latency, UI frame consistency, device warmth, and battery usage over several minutes. Record measurements rather than promising a speed target without evidence.
