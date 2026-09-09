import SwiftUI

struct ModePickerView: View {
    @Binding var selected: String
    let styles: WritingStyleStore
    let intelligence: IntelligenceService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing: WritingStyle?
    @State private var selectAfterSave = false
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 34.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Make it sound like you.")
                            .font(.system(size: titleSize, weight: .regular, design: .serif))
                            .tracking(-0.8).foregroundStyle(SaysoTheme.ink)
                        Text("Choose a mode, edit its prompt, or make your own.")
                            .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 22)
                    VStack(spacing: 4) {
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
                                    HStack(alignment: .top, spacing: 14) {
                                        Image(systemName: style.symbol)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(SaysoTheme.accent)
                                            .frame(width: 38, height: 38)
                                            .background(selected == style.id ? SaysoTheme.accent.opacity(0.09) : SaysoTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(style.title).font(.headline.weight(.medium)).foregroundStyle(SaysoTheme.ink)
                                            Text(style.isCustomized ? "Custom prompt" : style.subtitle)
                                                .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        Spacer(minLength: 4)
                                        Group {
                                            if selected == style.id {
                                                Image(systemName: "checkmark")
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(SaysoTheme.accent)
                                                    .padding(.top, 4).accessibilityHidden(true)
                                                    .transition(.opacity)
                                            }
                                        }
                                        .animation(reduceMotion ? nil : SaysoMotion.feedback, value: selected == style.id)
                                    }
                                    .padding(.leading, 14).padding(.vertical, 16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(.rect)
                                }.buttonStyle(SaysoPressButtonStyle()).accessibilityIdentifier("mode-\(style.id)")
                                    .accessibilityAddTraits(selected == style.id ? .isSelected : [])
                                    .accessibilityHint(style.mode == .custom && style.isBuiltIn ? "Opens your custom writing instructions" : "Use this mode for your next dictation")
                                if !style.isOriginal {
                                    Button {
                                        selectAfterSave = false
                                        editing = style
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.body).frame(width: 48, height: 52)
                                            .contentShape(.rect)
                                    }
                                    .buttonStyle(SaysoPressButtonStyle()).foregroundStyle(SaysoTheme.secondaryInk)
                                    .accessibilityLabel("Edit \(style.title) prompt")
                                    .accessibilityIdentifier("edit-mode-\(style.id)")
                                }
                            }
                            .padding(.trailing, 6)
                            .background {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(selected == style.id ? SaysoTheme.surface : Color.clear)
                                    .animation(reduceMotion ? nil : SaysoMotion.feedback, value: selected == style.id)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(selected == style.id ? SaysoTheme.accent.opacity(0.24) : Color.clear, lineWidth: 1)
                                    .animation(reduceMotion ? nil : SaysoMotion.feedback, value: selected == style.id)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    Button {
                        selectAfterSave = true
                        editing = WritingStyle(title: "", prompt: "")
                    } label: {
                        Label("Add mode", systemImage: "plus")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(SaysoPressButtonStyle()).foregroundStyle(SaysoTheme.accent)
                    .accessibilityIdentifier("addModeButton")
                    if let error = styles.storageError { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 16) {
                        Rectangle().fill(SaysoTheme.hairline).frame(height: 1).accessibilityHidden(true)
                        Label("Rewrites use Apple Intelligence. Your original words are always kept.", systemImage: "sparkles")
                            .font(.footnote).foregroundStyle(SaysoTheme.secondaryInk).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                        if !intelligence.isAvailable {
                            Text(intelligence.availabilityMessage).font(.footnote).foregroundStyle(SaysoTheme.secondaryInk)
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 30)
                .frame(maxWidth: 660).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("writingModesScrollView")
            .background(SaysoTheme.canvas)
            .tint(SaysoTheme.accent)
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
                        HStack(spacing: 14) {
                            Image(systemName: style.symbol)
                                .foregroundStyle(SaysoTheme.accent).frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(style.title).foregroundStyle(SaysoTheme.ink)
                                Text(style.isCustomized ? "Custom prompt" : style.isBuiltIn ? style.subtitle : "Your writing instructions")
                                    .font(.caption).foregroundStyle(SaysoTheme.secondaryInk)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }.frame(minHeight: 44).padding(.vertical, 4)
                    }.accessibilityIdentifier("edit-mode-\(style.id)")
                }
                Button { editing = WritingStyle(title: "", prompt: "") } label: {
                    Label("Add mode", systemImage: "plus.circle")
                }.accessibilityIdentifier("addModeButton")
            } footer: {
                Text("Edit a mode’s rewrite prompt or add a mode with its own name and instructions. Original always keeps your words untouched. Changes apply to future rewrites.")
            }.listRowBackground(SaysoTheme.surface)
            if let error = styles.storageError {
                Section { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden).background(SaysoTheme.canvas)
        .tint(SaysoTheme.accent)
        .accessibilityIdentifier("writingModesSettingsForm")
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
                    }.listRowBackground(SaysoTheme.surface)
                }
                Section {
                    TextEditor(text: $prompt).font(.body).lineSpacing(4).frame(minHeight: 240)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel(isLegacyCustom ? "Custom style instructions" : "Rewrite prompt")
                        .accessibilityIdentifier(isLegacyCustom ? "customStyleInstructions" : "rewritePromptEditor")
                } header: { Text("Rewrite prompt") } footer: {
                    Text("Describe the tone and format you want. For example: Make this a short, friendly reply. Keep my wording and skip the greeting. Sayso supplies the transcript and keeps its original available.")
                }.listRowBackground(SaysoTheme.surface)
                if let builtIn = style.builtInMode, builtIn != .custom, builtIn != .transcript {
                    Section {
                        Button("Restore default prompt") { prompt = builtIn.instructions; error = nil }
                            .disabled(prompt == builtIn.instructions)
                            .accessibilityIdentifier("resetModePromptButton")
                    }.listRowBackground(SaysoTheme.surface)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if !style.isBuiltIn && !isNew {
                    Section {
                        Button("Delete mode", role: .destructive) { confirmingDelete = true }
                            .accessibilityIdentifier("deleteModeButton")
                    } footer: { Text("Saved dictations keep their text and mode name when a mode is edited or deleted.") }
                    .listRowBackground(SaysoTheme.surface)
                }
            }
            .scrollContentBackground(.hidden).background(SaysoTheme.canvas)
            .tint(SaysoTheme.accent)
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
