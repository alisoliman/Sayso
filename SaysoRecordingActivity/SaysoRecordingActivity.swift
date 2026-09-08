import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct SaysoRecordingActivityBundle: WidgetBundle {
    var body: some Widget { SaysoRecordingActivity() }
}

struct SaysoRecordingActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            RecordingLockScreenView(context: context)
                .widgetURL(RecordingActivityAttributes.recordingURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RecordingSymbol(phase: context.state.phase, stale: context.recordingStatusIsStale, island: true)
                        .padding(.top, 5)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RecordingElapsed(context: context)
                        .font(.title3.monospacedDigit().weight(.medium))
                        .foregroundStyle(ActivityPalette.islandAccent)
                        .frame(width: 64)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.recordingStatusIsStale ? "Open Sayso" : context.state.phase.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.top, 7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if let note = context.state.note, !context.recordingStatusIsStale {
                            Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        if !context.state.phase.isTerminal, !context.recordingStatusIsStale {
                            RecordingControls(sessionID: context.attributes.sessionID, listening: context.state.phase == .listening, island: true)
                        } else {
                            Text(context.recordingStatusIsStale ? "Return to Sayso to check this recording." : context.state.phase == .ready ? "Open the Sayso keyboard and tap Insert." : "Tap to return to your words.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 5)
                }
            } compactLeading: {
                RecordingSymbol(phase: context.state.phase, stale: context.recordingStatusIsStale, island: true)
                    .font(.system(size: 16, weight: .semibold))
            } compactTrailing: {
                RecordingCompactTrailing(context: context)
            } minimal: {
                RecordingSymbol(phase: context.state.phase, stale: context.recordingStatusIsStale, island: true)
                    .font(.system(size: 15, weight: .semibold))
            }
            .widgetURL(RecordingActivityAttributes.recordingURL)
            .keylineTint(ActivityPalette.islandAccent)
        }
    }
}

private struct RecordingCompactTrailing: View {
    @Environment(\.isDynamicIslandLimitedInWidth) private var limitedInWidth
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        if limitedInWidth {
            // iOS 27's landscape island cannot expand horizontally. Keep a
            // glanceable microphone/status symbol beside the leading waveform;
            // duration remains available in the keyboard and expanded activity.
            RecordingSymbol(phase: context.state.phase, stale: context.recordingStatusIsStale,
                            island: true, listeningSymbol: "mic.fill")
                .font(.system(size: 14, weight: .semibold))
        } else {
            RecordingElapsed(context: context)
                .font(.caption.monospacedDigit().weight(.medium))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(ActivityPalette.islandAccent)
                .frame(maxWidth: 42)
        }
    }
}

private struct RecordingLockScreenView: View {
    @Environment(\.colorScheme) private var scheme
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                RecordingSymbol(phase: context.state.phase, stale: context.recordingStatusIsStale)
                    .font(.system(size: 23, weight: .medium))
                    .frame(width: 38, height: 38)
                    .background(ActivityPalette.accent(for: scheme).opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.recordingStatusIsStale ? "Open Sayso" : context.state.phase.title)
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(context.recordingStatusIsStale ? "Check your recording in the app." : context.state.note ?? subtitle)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 4)
                RecordingElapsed(context: context)
                    .font(.title2.monospacedDigit().weight(.medium))
                    .frame(width: 68)
            }
            if !context.state.phase.isTerminal, !context.recordingStatusIsStale {
                RecordingControls(sessionID: context.attributes.sessionID, listening: context.state.phase == .listening)
            }
        }
        .padding(16)
        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
        .activityBackgroundTint(ActivityPalette.canvas(for: scheme))
        .activitySystemActionForegroundColor(ActivityPalette.accent(for: scheme))
    }

    private var subtitle: String {
        switch context.state.phase {
        case .listening: "On-device · up to 10 minutes"
        case .finishing, .refining: "Your microphone is off."
        case .ready: "Open the Sayso keyboard and tap Insert."
        case .failed: "Open Sayso for the available text."
        case .cancelled: "Your microphone is off."
        }
    }
}

private struct RecordingElapsed: View {
    let context: ActivityViewContext<RecordingActivityAttributes>
    var body: some View {
        elapsedText.monospacedDigit()
            .accessibilityLabel("Recording duration")
            .accessibilityValue(context.recordingStatusIsStale && context.state.phase == .listening
                                ? Text("Unavailable. Open Sayso to check.") : elapsedText)
    }

    private var elapsedText: Text {
        if context.state.phase == .listening {
            guard !context.recordingStatusIsStale, let confirmedAt = context.state.confirmedAt else { return Text("—") }
            // The native timer stops at this snapshot's freshness bound even if
            // the app dies before another widget body evaluation can occur.
            let freshUntil = confirmedAt.addingTimeInterval(RecordingActivityAttributes.freshnessLifetime)
            let end = max(context.attributes.startedAt, min(context.attributes.endsAt, freshUntil))
            return Text(timerInterval: context.attributes.startedAt...end,
                        countsDown: false, showsHours: false)
        }
        let end = min(context.attributes.endsAt, context.state.stoppedAt ?? context.state.confirmedAt ?? context.attributes.startedAt)
        let seconds = max(0, Int(end.timeIntervalSince(context.attributes.startedAt)))
        return Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
    }
}

private extension ActivityViewContext where Attributes == RecordingActivityAttributes {
    var recordingStatusIsStale: Bool {
        if isStale { return true }
        guard !state.phase.isTerminal else { return false }
        guard let confirmedAt = state.confirmedAt else { return true }
        let freshUntil = confirmedAt.addingTimeInterval(RecordingActivityAttributes.freshnessLifetime)
        let deadline = state.phase == .listening ? min(attributes.endsAt, freshUntil) : freshUntil
        // Also fail closed when the system renders a previously fresh snapshot
        // after its deadline, before reflecting the ActivityKit stale state.
        return deadline <= Date()
    }
}

private struct RecordingSymbol: View {
    @Environment(\.colorScheme) private var scheme
    let phase: RecordingActivityAttributes.Phase
    let stale: Bool
    var island = false
    var listeningSymbol = "waveform"
    var body: some View {
        Image(systemName: stale ? "mic.slash" : phase == .listening ? listeningSymbol : phase.symbol)
            .foregroundStyle(island ? ActivityPalette.islandAccent : ActivityPalette.accent(for: scheme))
            .accessibilityLabel(stale ? "Recording status unavailable" : phase.title)
    }
}

private struct RecordingControls: View {
    @Environment(\.colorScheme) private var scheme
    let sessionID: UUID
    var listening = true
    var island = false
    var body: some View {
        HStack(spacing: 10) {
            Button(intent: CancelSaysoRecordingIntent(sessionID: sessionID)) {
                Label("Discard", systemImage: "xmark")
                    .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .accessibilityHint("Discard this active recording.")
            if listening {
                Button(intent: StopSaysoRecordingIntent(sessionID: sessionID)) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(island ? ActivityPalette.islandAccent : ActivityPalette.accent(for: scheme))
                .foregroundStyle(island ? ActivityPalette.islandInk : ActivityPalette.onAccent(for: scheme))
                .accessibilityHint("Stop the microphone and finish your text.")
            }
        }
    }
}

private enum ActivityPalette {
    // Resolve the same SwiftUI environment for both the system background and
    // text. A dynamic UIColor can resolve differently in ActivityKit's host,
    // producing a light background behind Lock Screen white text.
    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? islandAccent : Color(red: 0.30, green: 0.22, blue: 0.43)
    }
    static func onAccent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? islandInk : .white
    }
    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.075, green: 0.075, blue: 0.09) : Color(red: 0.975, green: 0.97, blue: 0.96)
    }
    static let islandAccent = Color(red: 0.81, green: 0.72, blue: 0.95)
    static let islandInk = Color(red: 0.12, green: 0.10, blue: 0.16)
}
