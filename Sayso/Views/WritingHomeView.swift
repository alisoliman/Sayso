import SwiftUI

/// The opening page stays independent of live audio updates.
struct WritingHomeView: View {
    let recentEntry: Dictation?
    let onHistory: () -> Void
    let onRecent: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ScaledMetric(relativeTo: .largeTitle) private var idleTitleSize = 46.0
    private var compactHeight: Bool { verticalSizeClass == .compact }

    var body: some View {
        VStack(alignment: .leading, spacing: compactHeight ? 16 : 28) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Your writing space")
                Text(compactHeight ? "From thought to text." : "From thought\nto text.")
                    .font(compactHeight ? .system(.title2, design: .serif) : .system(size: idleTitleSize, weight: .regular, design: .serif))
                    .tracking(-1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("homeHeadline")
                Text("Say what’s on your mind. Make it a message, a note, or something more.")
                    .font(.body).lineSpacing(4)
                    .foregroundStyle(SaysoTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if recentEntry == nil && !compactHeight && !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 24) {
                    VoiceEmblem().frame(width: 64, height: 60)
                        .padding(18)
                        .background(SaysoTheme.accentSoft, in: .rect(cornerRadius: 24))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A little less typing.")
                            .font(.headline).foregroundStyle(SaysoTheme.ink)
                        Text("Choose a mode below, then tap to start speaking.")
                            .font(.subheadline).lineSpacing(3)
                            .foregroundStyle(SaysoTheme.secondaryInk)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SaysoTheme.paper, in: .rect(cornerRadius: 28))
            }

            if let entry = recentEntry {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Eyebrow(text: "Pick up a thought")
                        }
                        Spacer()
                        Button(action: onHistory) {
                            Text("View all")
                                .font(.subheadline.weight(.medium))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .accessibilityIdentifier("viewAllHistoryButton")
                    }
                    Button(action: onRecent) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(entry.text).font(.body).lineSpacing(4).lineLimit(2)
                                .foregroundStyle(SaysoTheme.ink)
                                .multilineTextAlignment(.leading)
                            HStack {
                                Label(entry.modeTitle, systemImage: entry.modeSymbol)
                                Spacer()
                                Image(systemName: "arrow.up.right").accessibilityHidden(true)
                            }
                            .font(.caption.weight(.medium)).foregroundStyle(SaysoTheme.secondaryInk)
                        }
                        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(SaysoTheme.paper, in: .rect(cornerRadius: 24))
                        .contentShape(.rect)
                    }
                    .buttonStyle(SaysoPressButtonStyle())
                    .accessibilityIdentifier("recentThoughtButton")
                    .accessibilityHint("Open your most recent saved dictation")
                }
            } else if !compactHeight && !dynamicTypeSize.isAccessibilitySize {
                Label("No account. Just your words.", systemImage: "lock")
                    .font(.footnote).foregroundStyle(SaysoTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
            }
        }
    }

}
