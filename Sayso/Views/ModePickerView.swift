import SwiftUI

struct ModePickerView: View {
    @Binding var selected: String
    let styles: WritingStyleStore
    let intelligence: IntelligenceService
    @Environment(\.dismiss) private var dismiss
    @State private var editing: WritingStyle?
    @State private var selectAfterSave = false
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 31.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Make it sound like you.").font(.system(size: titleSize, weight: .medium, design: .serif)).tracking(-0.8)
                        Text("Choose a mode, edit its prompt, or make your own.")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }.padding(.top, 20)
                    VStack(spacing: 2) {
                        ForEach(styles.styles) { style in
                            HStack(spacing: 0) {
                                Button {
                                    if style.mode == .custom && style.isBuiltIn {
                                        selectAfterSave = true
                                        editing = style
                                    } else {
                                        selected = style.id
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: style.symbol).font(.system(size: 21))
                                            .foregroundStyle(selected == style.id ? SaysoTheme.accent : .secondary)
                                            .frame(width: 32, height: 48)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(style.title).font(.headline).foregroundStyle(.primary)
                                            Text(style.isCustomized ? "Custom prompt" : style.subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading).lineLimit(2)
                                        }
                                        Spacer(minLength: 4)
                                        if selected == style.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(SaysoTheme.accent)
                                        }
                                    }
                                    .padding(.leading, 12).padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(.rect)
                                }.buttonStyle(.plain).accessibilityIdentifier("mode-\(style.id)")
                                    .accessibilityAddTraits(selected == style.id ? .isSelected : [])
                                if !style.isOriginal {
                                    Button {
                                        selectAfterSave = false
                                        editing = style
                                    } label: {
                                        Image(systemName: "pencil").frame(width: 44, height: 48)
                                    }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)
                                    .accessibilityLabel("Edit \(style.title) prompt")
                                    .accessibilityIdentifier("edit-mode-\(style.id)")
                                }
                            }
                            .padding(.trailing, 6)
                            .background(selected == style.id ? SaysoTheme.accent.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    Button {
                        selectAfterSave = true
                        editing = WritingStyle(title: "", prompt: "")
                    } label: {
                        Label("Add mode", systemImage: "plus.circle").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.accessibilityIdentifier("addModeButton")
                    if let error = styles.storageError { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    Label("Rewrites use Apple Intelligence. Your original words are always kept.", systemImage: "sparkles")
                        .font(.footnote).foregroundStyle(.secondary).lineSpacing(3)
                    if !intelligence.isAvailable {
                        Text(intelligence.availabilityMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 30)
            }
            .background(SaysoTheme.canvas)
            .navigationTitle("Modes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { style in
                WritingStyleEditor(style: style, styles: styles) { saved in
                    editing = nil
                    if selectAfterSave {
                        selected = saved.id
                        dismiss()
                    }
                }
            }
        }
    }
}

/// The same saved prompts are used for recording, imports and every Rewrite menu.
struct WritingModesSettingsView: View {
    let styles: WritingStyleStore
    @State private var editing: WritingStyle?

    var body: some View {
        Form {
            Section {
                ForEach(styles.styles.filter { !$0.isOriginal }) { style in
                    Button { editing = style } label: {
                        HStack {
                            Label(style.title, systemImage: style.symbol).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.frame(minHeight: 32)
                    }.accessibilityIdentifier("edit-mode-\(style.id)")
                }
                Button { editing = WritingStyle(title: "", prompt: "") } label: {
                    Label("Add mode", systemImage: "plus.circle")
                }.accessibilityIdentifier("addModeButton")
            } footer: {
                Text("Edit a mode’s rewrite prompt or add a mode with its own name and instructions. Original always keeps your words untouched. Changes apply to future rewrites.")
            }
            if let error = styles.storageError {
                Section { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Writing modes").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { style in
            WritingStyleEditor(style: style, styles: styles) { _ in editing = nil }
        }
    }
}

struct WritingStyleEditor: View {
    let style: WritingStyle
    let styles: WritingStyleStore
    let onSave: (WritingStyle) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var prompt: String
    @State private var error: String?
    @State private var confirmingDelete = false

    init(style: WritingStyle, styles: WritingStyleStore, onSave: @escaping (WritingStyle) -> Void) {
        self.style = style
        self.styles = styles
        self.onSave = onSave
        _title = State(initialValue: style.title)
        _prompt = State(initialValue: style.prompt)
    }

    private var isNew: Bool { !styles.styles.contains { $0.id == style.id } }
    private var isLegacyCustom: Bool { style.builtInMode == .custom }
    private var navigationTitle: String {
        if isNew { return "New mode" }
        if isLegacyCustom { return "Custom mode" }
        return style.title + (style.isBuiltIn ? " prompt" : " mode")
    }
    private var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if !style.isBuiltIn {
                    Section("Name") {
                        TextField("For example, Team update", text: $title)
                            .textInputAutocapitalization(.words)
                            .accessibilityLabel("Mode name").accessibilityIdentifier("modeNameField")
                    }
                }
                Section {
                    TextEditor(text: $prompt).frame(minHeight: 200)
                        .accessibilityLabel(isLegacyCustom ? "Custom style instructions" : "Rewrite prompt")
                        .accessibilityIdentifier(isLegacyCustom ? "customStyleInstructions" : "rewritePromptEditor")
                } header: { Text("Rewrite prompt") } footer: {
                    Text("Describe the tone and format you want. For example: Make this a short, friendly reply. Keep my wording and skip the greeting. Sayso supplies the transcript and keeps its original available.")
                }
                if let builtIn = style.builtInMode, builtIn != .custom, builtIn != .transcript {
                    Section {
                        Button("Restore default prompt") { prompt = builtIn.instructions; error = nil }
                            .disabled(prompt == builtIn.instructions)
                            .accessibilityIdentifier("resetModePromptButton")
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if !style.isBuiltIn && !isNew {
                    Section {
                        Button("Delete mode", role: .destructive) { confirmingDelete = true }
                            .accessibilityIdentifier("deleteModeButton")
                    } footer: { Text("Saved dictations keep their text and mode name when a mode is edited or deleted.") }
                }
            }
            .navigationTitle(navigationTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("cancelModeButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isLegacyCustom ? "Done" : "Save") {
                        let updated = WritingStyle(id: style.id, title: title, prompt: prompt)
                        if styles.save(updated) { onSave(styles.style(for: style.id)) }
                        else { error = styles.validationError ?? styles.storageError ?? "This mode couldn’t be saved. Please try again." }
                    }
                    .disabled(!valid)
                    .accessibilityIdentifier(isLegacyCustom ? "saveCustomStyleButton" : "saveModeButton")
                }
            }
            .confirmationDialog("Delete \(style.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete mode", role: .destructive) {
                    if styles.delete(style) { dismiss() }
                    else { error = styles.validationError ?? styles.storageError }
                }.accessibilityIdentifier("confirmDeleteModeButton")
            } message: { Text("This removes the mode and its prompt. Your saved dictations stay in History.") }
        }
        .presentationDetents(isLegacyCustom ? [.medium, .large] : [.large])
    }
}
