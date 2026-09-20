import SwiftUI

/// Warm paper, forest ink, and a clear recording accent. Keep reading surfaces opaque;
/// system glass is reserved for navigation above the content.
enum SaysoTheme {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }

    static let accent = adaptive(0x155E52, 0x9DDAC6)
    static let onAccent = adaptive(0xFFFFFF, 0x103C33)
    static let canvas = adaptive(0xF5F3EC, 0x121C19)
    static let surface = adaptive(0xEAECE4, 0x24312C)
    static let paper = adaptive(0xFFFEF9, 0x1B2823)
    static let accentSoft = adaptive(0xE0EEE5, 0x263E33)
    static let recording = adaptive(0xA33E27, 0xFFB49B)
    static let ink = adaptive(0x20352D, 0xF0F4ED)
    static let secondaryInk = adaptive(0x5C6961, 0xB0BFB5)
    static let hairline = adaptive(0xD4DBD1, 0x46594E)
    static let muted = secondaryInk
}

/// Motion follows a change of intent, never a clock. Keep it brief enough that
/// another tap can interrupt it; recording and insertion never wait for a finish.
enum SaysoMotion {
    static let feedback = Animation.easeOut(duration: 0.16)
    static let settle = Animation.spring(response: 0.30, dampingFraction: 0.88)
    static let stateChange = Animation.easeInOut(duration: 0.26)

    static func content(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .asymmetric(
            // Clear the previous words before revealing the next surface.
            // Only presentation is staged; actions and model state are immediate.
            insertion: .opacity.combined(with: .offset(y: 8))
                .animation(.easeOut(duration: 0.22).delay(0.10)),
            removal: .opacity.animation(.easeOut(duration: 0.09)))
    }
}

struct QuietBackground: View {
    var body: some View { SaysoTheme.canvas.ignoresSafeArea() }
}

struct SaysoPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(isEnabled ? SaysoTheme.onAccent : SaysoTheme.secondaryInk)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(minHeight: 52)
            .background(isEnabled ? SaysoTheme.accent : SaysoTheme.surface, in: .rect(cornerRadius: 20))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : (configuration.isPressed ? SaysoMotion.feedback : SaysoMotion.settle), value: configuration.isPressed)
    }
}

struct SaysoQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? SaysoTheme.accent : SaysoTheme.secondaryInk)
            .frame(minWidth: 44, minHeight: 44)
            .background(SaysoTheme.surface, in: .rect(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : SaysoMotion.feedback, value: configuration.isPressed)
    }
}

/// Direct feedback for plain controls; their surface and hit area stay owned
/// by the caller. System glass, menus and navigation keep their native motion.
struct SaysoPressButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(!isEnabled ? 0.4 : (configuration.isPressed ? 0.68 : 1))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : SaysoMotion.feedback, value: configuration.isPressed)
    }
}

struct RoundButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(SaysoPressButtonStyle())
        .background(SaysoTheme.paper, in: .circle)
        .overlay { Circle().strokeBorder(SaysoTheme.hairline, lineWidth: 1) }
        .foregroundStyle(SaysoTheme.ink)
        .accessibilityLabel(label)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).tracking(1.6)
            .foregroundStyle(SaysoTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A quiet, static voice signature. Unlike the input meter, it never implies
/// microphone activity. Native vector geometry stays crisp at every scale.
struct VoiceEmblem: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Canvas { context, size in
            let heights: [CGFloat] = [0.24, 0.58, 0.88, 1, 0.72, 0.43, 0.19]
            let step = size.width / CGFloat(heights.count)
            let width = step * 0.57
            for (index, proportion) in heights.enumerated() {
                let height = size.height * proportion
                let rect = CGRect(x: CGFloat(index) * step + (step - width) / 2,
                                  y: (size.height - height) / 2, width: width, height: height)
                let path = Path(roundedRect: rect, cornerRadius: width / 2)
                let opacity = contrast == .increased ? 1 : 0.46 + 0.54 * proportion
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [SaysoTheme.accent.opacity(opacity * 0.68), SaysoTheme.accent.opacity(opacity)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            }
        }
        .accessibilityHidden(true)
    }
}

struct WaveformView: View {
    var recording: Bool
    var level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // The input level drives the meter. Silence and Stop settle to a line;
        // Reduce Motion keeps that line still while words and status update.
        let energy = recording && !reduceMotion ? min(max(level * 2.8, 0), 1) : 0
        // This outer drawing area follows layout immediately. Only its inner
        // bars interpolate: recognition often changes level and line count in
        // the same update, which must not animate the meter through the words.
        Color.clear
            .overlay {
                VoiceLevelShape(energy: energy)
                    .fill(SaysoTheme.accent.opacity(contrast == .increased ? 1 : 0.8))
                    .animation(reduceMotion ? nil : .easeOut(duration: recording ? 0.16 : 0.22), value: energy)
            }
            .geometryGroup()
            .clipped()
        .accessibilityHidden(true)
    }
}

private struct VoiceLevelShape: Shape {
    var energy: Double
    var animatableData: Double {
        get { energy }
        set { energy = newValue }
    }

    func path(in bounds: CGRect) -> Path {
        var path = Path()
        let count = 43
        let step = bounds.width / CGFloat(count)
        for index in 0..<count {
            let position = Double(index) / Double(count - 1)
            let envelope = pow(sin(position * .pi), 1.6)
            let signature = 0.35 + 0.65 * abs(sin(Double(index) * 0.81))
            let height = max(4, envelope * signature * energy * bounds.height)
            let rect = CGRect(x: bounds.minX + CGFloat(index) * step + (step - 3) / 2,
                              y: bounds.midY - height / 2, width: 3, height: height)
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 2, height: 2))
        }
        return path
    }
}
