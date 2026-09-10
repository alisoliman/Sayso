import SwiftUI

/// Sharing is a deliberate action, separate from saving private dictation history.
struct KeyboardSendButton: View {
    let text: String
    let id: UUID
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        Button {
            do {
                _ = try KeyboardHandoff().publish(text: text, id: id)
                failed = false
                message = "Return to the app you’re writing in, switch to the Sayso keyboard, and tap Insert. Your text is available for 10 minutes."
            } catch {
                failed = true
                message = error.localizedDescription
            }
        } label: {
            Image(systemName: "keyboard").font(.system(size: 18)).frame(width: 42, height: 42)
        }
        .buttonStyle(.glass).buttonBorderShape(.circle)
        .accessibilityLabel("Send to keyboard")
        .accessibilityHint("Make this text available to insert in another app")
        .accessibilityIdentifier("sendToKeyboardButton")
        .alert(failed ? "Couldn’t share with keyboard" : "Ready in your keyboard", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }
}

struct KeyboardSetupView: View {
    @State private var clearMessage: String?
    var body: some View {
        Form {
            Section {
                Text("Your words, wherever you write.")
                    .font(.title2.weight(.medium)).fontDesign(.serif).padding(.vertical, 10)
                Text("Add Sayso in Settings → General → Keyboard → Keyboards → Add New Keyboard.")
                Text("Enable Full Access for recording controls. You can insert shared text without it.").foregroundStyle(.secondary)
            } header: { Text("Set up once") }
            Section {
                Label("Start Dictate in another app in Sayso, or use your Keyboard Dictation shortcut.", systemImage: "mic")
                Label("Return to your text field and choose Sayso from the globe menu.", systemImage: "keyboard")
                Label("Choose a mode, then tap Stop & insert. Your words appear at the cursor.", systemImage: "arrow.turn.down.left")
            } header: { Text("Dictate into another app") } footer: {
                Text("Each recording starts in Sayso and ends after 10 minutes. Keep the same text field open while your words finish. If you leave the field, tap Insert when you return. You can also stop from the Live Activity and tap Insert.")
            }
            Section {
                Label("Tap Send to keyboard beside any finished text in Sayso. Return to your app and tap Insert.", systemImage: "text.bubble")
                Label("Use the globe button to switch back to your usual keyboard whenever you need to type.", systemImage: "globe")
            } header: { Text("Your words, your keyboard") } footer: {
                Text("Shared text is available for 10 minutes. Sayso doesn’t read your clipboard or surrounding text, and sends no audio or text to a server. Password fields and some apps use the system keyboard.")
            }
            Section {
                Button("Clear shared text", role: .destructive) {
                    do { try KeyboardHandoff().clear(); clearMessage = "The text shared with your keyboard has been removed." }
                    catch { clearMessage = error.localizedDescription }
                }
            } footer: { Text("Clearing shared text leaves your dictation history in Sayso.") }
        }
        .navigationTitle("Sayso keyboard").navigationBarTitleDisplayMode(.inline)
        .alert("Shared text", isPresented: Binding(get: { clearMessage != nil }, set: { if !$0 { clearMessage = nil } })) {
            Button("OK") { clearMessage = nil }
        } message: { Text(clearMessage ?? "") }
    }
}
