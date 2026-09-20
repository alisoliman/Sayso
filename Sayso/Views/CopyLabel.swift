import SwiftUI

struct CopyLabel: View {
    let copied: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Reserve the feedback width so copying never shifts adjacent actions.
            Label("Copied", systemImage: "document.on.document")
                .hidden().accessibilityHidden(true)
            Label {
                Text(copied ? "Copied" : "Copy")
                    .contentTransition(reduceMotion ? .identity : .opacity)
            } icon: {
                Image(systemName: copied ? "checkmark" : "document.on.document")
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
        }
        .animation(reduceMotion ? nil : SaysoMotion.feedback, value: copied)
    }
}
