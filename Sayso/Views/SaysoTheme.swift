import SwiftUI

// Native glass belongs to controls; the writing surface stays quiet and readable.
enum SaysoTheme {
    static let accent = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 0.81, green: 0.72, blue: 0.95, alpha: 1) : UIColor(red: 0.30, green: 0.22, blue: 0.43, alpha: 1)
    })
    static let onAccent = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 0.12, green: 0.10, blue: 0.16, alpha: 1) : .white
    })
    static let canvas = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 0.075, green: 0.075, blue: 0.09, alpha: 1) : UIColor(red: 0.975, green: 0.97, blue: 0.96, alpha: 1)
    })
    static let ink = Color.primary
    static let muted = Color.secondary
}

struct QuietBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            SaysoTheme.canvas
            RadialGradient(colors: [SaysoTheme.accent.opacity(scheme == .dark ? 0.12 : 0.045), .clear], center: .init(x: 0.65, y: 0.46), startRadius: 10, endRadius: 360)
        }.ignoresSafeArea()
    }
}

struct RoundButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                .frame(width: 46, height: 46)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
    }
}

struct WaveformView: View {
    var recording: Bool
    var level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !recording || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let count = 43
                let step = size.width / CGFloat(count)
                for index in 0..<count {
                    let position = Double(index) / Double(count - 1)
                    let envelope = pow(sin(position * .pi), 1.6)
                    let signature = 0.35 + 0.65 * abs(sin(Double(index) * 0.81))
                    let motion = recording && !reduceMotion ? 0.45 + 0.55 * abs(sin(time * 3.1 + Double(index) * 0.43)) : 1
                    let amplitude = recording ? 0.15 + min(level * 2.8, 1) * 0.85 : 0.65
                    let height = max(4, envelope * signature * motion * amplitude * size.height)
                    let rect = CGRect(x: CGFloat(index) * step + (step - 3) / 2, y: (size.height - height) / 2, width: 3, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(SaysoTheme.accent.opacity(0.24 + envelope * (scheme == .dark ? 0.64 : 0.66))))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
