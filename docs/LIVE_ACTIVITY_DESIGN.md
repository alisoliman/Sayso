# Recording Live Activity

Implemented against the installed iOS 26.5 SDK with Xcode 26.6. No iOS 27 or physical-device verification is implied.

## System integration

`SaysoRecordingActivity` is a native WidgetKit extension containing an ActivityConfiguration for `RecordingActivityAttributes`. It presents a Lock Screen recording timer, expanded Dynamic Island controls, compact waveform/timer and minimal status. The native timer uses a bounded date interval, so the app does not send updates each second. Activity content includes a session ID, dates, phase and a bounded status note; it never includes dictated text or audio. System surfaces handle their normal layout and state transitions.

The app's `RecordingActivityCoordinator` implements injectable `RecordingActivityCoordinating`. `start(sessionID:startedAt:endsAt:)` requires the app foreground and enabled Live Activities, accepts a maximum ten-minute interval, removes orphaned older activities and propagates request errors. `update(phase:note:)` supports listening, finishing, refining, ready, failed and cancelled. It freezes elapsed time when listening ends. `end(phase:note:)` removes cancelled activities immediately and briefly leaves a terminal status for other outcomes. The app must start actual capture in the foreground and stop it on timeout; a Live Activity itself does neither. [Apple ActivityKit implementation guide](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

The coordinator observes ActivityKit dismissal/end and authorization changes. `onUnexpectedEnd(sessionID)` tells the recording controller to end its matching cross-app session if its visible system activity becomes unavailable. Updates and ending retain the exact Activity instance across suspension so old completions cannot clear a newly started activity. The controller remains responsible for generation guards and capture cleanup.

## Stop and Cancel

The native controls use `Button(intent:)` with `StopSaysoRecordingIntent` / `CancelSaysoRecordingIntent`, conforming to `LiveActivityIntent`. Apple explicitly documents that this protocol makes the intent run in the containing app process. Both actions are background-only and perform one operation: send a short-lived, session-scoped Stop or Cancel command through the App Group mailbox. They never create a new recording, activate audio or open the app. The existing capture owner receives the command and updates the activity. Expired, absent or mismatched session IDs fail harmlessly through the mailbox validation. [Apple: widget and Live Activity interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)

The app and widget compile the same intent declarations and Foundation-only command store, and carry the same App Group entitlement. Activity attributes/intents are in `RecordingActivityShared`, which is deliberately excluded from the keyboard target. Keyboard Full Access remains optional: it is needed to send its own Stop/Cancel command, while explicit result insertion remains read-only. The widget does not have the keyboard's Full Access restriction.

Apple documents that Lock Screen buttons do not execute until the person authenticates/unlocks. Less restrictive protection for non-text command metadata does not bypass that system rule. The transcript handoff retains complete file protection. UI validation must distinguish a visible control from successfully dispatched Stop/Cancel. [Apple: interactivity behavior](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)

Tapping the activity outside its controls opens `sayso://recording`, the existing recording scene. This URL must never begin a fresh recording. The deep link is attached once per presentation through `widgetURL`. [Apple: launching from a Live Activity](https://developer.apple.com/documentation/activitykit/launching-your-app-from-a-live-activity)

## Configuration and verification

The app declares `NSSupportsLiveActivities = true` and `UIBackgroundModes = [audio]`. The embedded widget declares `com.apple.widgetkit-extension`. Activity creation uses `pushType: nil`; no push service, account, entitlement for remote notifications or network transport is introduced.

Independent source typechecks passed with Swift 5 language mode, default MainActor isolation and the installed arm64 iOS 26.5 simulator SDK. The complete widget, intents and actual command store also pass `-application-extension` checking. This confirms source/API compatibility only. Integrated builds/tests and actual Lock Screen/Dynamic Island behavior still need separate evidence.

Required acceptance includes permission-disabled startup preventing cross-app capture; actual foreground recording followed by app switch; timer and microphone status; Stop/Cancel reaching the correct active session; authenticated Lock Screen interaction; normal/timed/interrupted ending; activity dismissal or permission revocation stopping capture; changed session IDs rejecting old controls; app termination orphan cleanup; and light/dark, VoiceOver and large text layouts. Device testing must establish real microphone and ActivityKit behavior before release.
