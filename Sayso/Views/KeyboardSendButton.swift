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
            Image(systemName: "keyboard").font(.system(size: 18)).frame(width: 44, height: 44)
        }
        .buttonStyle(SaysoQuietButtonStyle())
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
                Text("Full Access can stay off for inserting finished text. Turn it on if you also want Stop and Discard in the keyboard.").foregroundStyle(.secondary)
            } header: { Text("Set up once") }
            Section {
                Label("Record in Sayso, or start with your Action button shortcut.", systemImage: "mic")
                Label("Tap Send to keyboard beside your finished text.", systemImage: "keyboard")
                Label("Return to your app. Hold the globe key, choose Sayso, then tap Insert.", systemImage: "arrow.turn.down.left")
            } header: { Text("When an idea comes") } footer: {
                Text("Only text you send is available in the keyboard, for 10 minutes. Sayso removes expired shared text when reopened. Password fields and some apps use the system keyboard.")
            }
            Section {
                Label("Choose Dictate in another app in Sayso, or use the Keyboard Dictation shortcut on your Action button.", systemImage: "mic")
                Label("Return to your text field while recording. Tap Stop in the Sayso keyboard or Live Activity, then Insert.", systemImage: "keyboard")
            } header: { Text("Keep writing in your app") } footer: {
                Text("Each recording starts in Sayso and ends after 10 minutes. Live Activities must be allowed. Full Access enables keyboard controls; Sayso doesn’t read your clipboard or surrounding text, and sends no audio or text to a server.")
            }
            Section {
                Button("Clear shared text", role: .destructive) {
                    do { try KeyboardHandoff().clear(); clearMessage = "The text shared with your keyboard has been removed." }
                    catch { clearMessage = error.localizedDescription }
                }
            } footer: { Text("Clearing shared text leaves your dictation history in Sayso.") }
        }
        .scrollContentBackground(.hidden)
        .background(SaysoTheme.canvas)
        .navigationTitle("Sayso keyboard").navigationBarTitleDisplayMode(.inline)
        .alert("Shared text", isPresented: Binding(get: { clearMessage != nil }, set: { if !$0 { clearMessage = nil } })) {
            Button("OK") { clearMessage = nil }
        } message: { Text(clearMessage ?? "") }
    }
}
