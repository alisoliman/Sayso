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
- During dictation, receive a call, disconnect wired/Bluetooth audio, switch apps, and lock the phone. Recording should stop; captured text is preserved.
- Confirm Home and results offer live recording only, with no audio-import action.
- Background immediately after stopping. Verify history contains the captured original even when refinement cannot finish.
- Turn off history, dictate, and relaunch. New dictation is absent; previously stored entries stay until deleted.
- Edit a history entry, relaunch, and verify original and edited text. Rewrite it from History and from Home after a manual correction; the correction must remain. Original explicitly restores the archive. Test deletion and cancellation of deletion.

## Writing quality

Run the fixed local-model corpus in the evaluation artifact and additional English/Dutch (or chosen-language) examples. Compare the original manually. Check names, numbers, money, times, negations, uncertainty, self-corrections, mixed languages, and quoted instructions. Test all modes. Deliberately exceed model context; no silent truncation or replacement with an empty result.

A successful generation is not a fidelity guarantee. New numeric forms are rejected, but omitted/reassigned details or spelled-out numbers can still need review.

## Interaction and integration

- Assign Start Dictation to the Action button through Shortcuts; cold/warm launches start exactly once after the app is foreground. Siri and sayso://record route into the same permission/lifecycle behavior.
- Copy into Notes and Messages; use native Share. Sayso does not send the message itself.
- Light/dark appearance, largest accessibility sizes, VoiceOver, Reduce Motion, Increase Contrast, and Reduce Transparency.
- Verify microphone/stop hit areas, text selection, mode-picker dismissal, sheets, keyboard editing, and long-history scrolling. During a long recording, newest words stay visible; scroll back and confirm recognition does not force you away; Latest words resumes following.
- Measure first and warm recording start, stop-to-original latency, stop-to-refinement latency, UI frame consistency, device warmth, and battery usage over several minutes. Record measurements rather than promising a speed target without evidence.
