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
                    RecordingPhaseTitle(phase: context.state.phase, stale: context.recordingStatusIsStale)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.top, 7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if let note = context.state.note, !context.recordingStatusIsStale {
                            Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                .contentTransition(.identity).transition(.identity)
                        }
                        if !context.state.phase.isTerminal, !context.recordingStatusIsStale {
                            RecordingControls(sessionID: context.attributes.sessionID, listening: context.state.phase == .listening, island: true)
                                .transition(.identity)
                        } else {
                            Text(context.recordingStatusIsStale ? "Return to Sayso to check this recording." : context.state.phase == .ready ? "Open the Sayso keyboard and tap Insert." : "Tap to return to your words.")
                                .font(.caption).foregroundStyle(.secondary)
                                .contentTransition(.identity).transition(.identity)
                        }
                    }.padding(.top, 5)
                }
            } compactLeading: {
                RecordingSymbol(phase: context.state.phase, stale: context.recordingStatusIsStale, island: true, animatesPhase: false)
                    .font(.system(size: 16, weight: .semibold))
            } compactTrailing: {
                RecordingCompactTrailing(context: context)
            } minimal: {
                RecordingSymbol(phase: context.state.phase, stale: context.recordingStatusIsStale, island: true, animatesPhase: false)
                    .font(.system(size: 15, weight: .semibold))
            }
            .widgetURL(RecordingActivityAttributes.recordingURL)
            .keylineTint(ActivityPalette.islandAccent)
        }
    }
}

private struct RecordingPhaseTitle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    let phase: RecordingActivityAttributes.Phase
    let stale: Bool

    private var title: String { stale ? "Open Sayso" : phase.title }
    private var animates: Bool { !reduceMotion && !luminanceReduced && !stale }

    var body: some View {
        Text(title)
            // One quiet content change marks a phase update. Freshness ticks
            // do not retrigger it, and stale status appears immediately.
            .contentTransition(animates ? .opacity : .identity)
            .transition(.identity)
            .animation(animates ? .easeOut(duration: 0.18) : nil, value: title)
            .animation(nil, value: reduceMotion)
            .animation(nil, value: luminanceReduced)
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
                            island: true, listeningSymbol: "mic.fill", animatesPhase: false)
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
                VStack(alignment: .leading, spacing: 3) {
                    RecordingPhaseTitle(phase: context.state.phase, stale: context.recordingStatusIsStale)
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(context.recordingStatusIsStale ? "Check your recording in the app." : context.state.note ?? subtitle)
                        .font(.caption).foregroundStyle(ActivityPalette.secondaryInk(for: scheme)).lineLimit(2)
                        .contentTransition(.identity)
                }
                Spacer(minLength: 4)
                RecordingElapsed(context: context)
                    .font(.title2.monospacedDigit().weight(.medium))
                    .frame(width: 68)
            }
            if !context.state.phase.isTerminal, !context.recordingStatusIsStale {
                RecordingControls(sessionID: context.attributes.sessionID, listening: context.state.phase == .listening)
                    .transition(.identity)
            }
        }
        .padding(16)
        .foregroundStyle(ActivityPalette.ink(for: scheme))
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
            // Keep the narrow timer stable. The native date interval still
            // owns ticking and its existing freshness bound.
            .contentTransition(.identity)
            .transition(.identity)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    let phase: RecordingActivityAttributes.Phase
    let stale: Bool
    var island = false
    var listeningSymbol = "waveform"
    var animatesPhase = true

    private var symbol: String { stale ? "mic.slash" : phase == .listening ? listeningSymbol : phase.symbol }
    private var animates: Bool { animatesPhase && !reduceMotion && !luminanceReduced && !stale }

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(island ? ActivityPalette.islandAccent : ActivityPalette.accent(for: scheme))
            .contentTransition(animates ? .opacity : .identity)
            .transition(.identity)
            .animation(animates ? .easeOut(duration: 0.18) : nil, value: symbol)
            .animation(nil, value: reduceMotion)
            .animation(nil, value: luminanceReduced)
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
            .buttonBorderShape(.capsule)
            .tint(.secondary)
            .accessibilityHint("Discard this active recording.")
            if listening {
                Button(intent: StopSaysoRecordingIntent(sessionID: sessionID)) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(island ? ActivityPalette.islandAccent : ActivityPalette.accent(for: scheme))
                .foregroundStyle(island ? ActivityPalette.islandInk : ActivityPalette.onAccent(for: scheme))
                .transition(.identity)
                .accessibilityHint("Stop the microphone and finish your text.")
            }
        }
        // Intent buttons keep native press feedback; never retain a fading
        // Stop target after capture has entered its processing phase.
        .animation(nil, value: listening)
    }
}

private enum ActivityPalette {
    // Resolve the same SwiftUI environment for both the system background and
    // text. A dynamic UIColor can resolve differently in ActivityKit's host,
    // producing a light background behind Lock Screen white text.
    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? islandAccent : color(0x503968)
    }
    static func onAccent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? islandInk : .white
    }
    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark ? color(0x141218) : color(0xF8F6F2)
    }
    static func ink(for scheme: ColorScheme) -> Color {
        scheme == .dark ? color(0xF5F0FA) : color(0x261F2F)
    }
    static func secondaryInk(for scheme: ColorScheme) -> Color {
        scheme == .dark ? color(0xB8AEBD) : color(0x6D6674)
    }
    static let islandAccent = color(0xCEB8F2)
    static let islandInk = color(0x261F2F)

    private static func color(_ value: UInt32) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}
