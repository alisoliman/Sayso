import SwiftUI

struct ModePickerView: View {
    @Binding var selected: String
    let styles: WritingStyleStore
    let intelligence: IntelligenceService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editing: WritingStyle?
    @State private var selectAfterSave = false
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 36.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) {
                            Eyebrow(text: "A voice for every thought")
                            Text("Your words.\nYour way.")
                                .font(.system(size: titleSize, weight: .regular, design: .serif))
                                .tracking(-0.8).foregroundStyle(SaysoTheme.ink)
                            Text("Keep what you said, or give it a little shape.")
                                .font(.body).foregroundStyle(SaysoTheme.secondaryInk)
                                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        }.padding(.top, 12)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Just as you said it")
                        ForEach(styles.styles.filter(\.isOriginal)) { style in
                            modeCard(style)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Ready to write")
                        ForEach(styles.styles.filter { $0.isBuiltIn && !$0.isOriginal && $0.mode != .custom }) { style in
                            modeCard(style)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Make it personal")
                        ForEach(styles.styles.filter { !$0.isBuiltIn || $0.mode == .custom }) { style in
                            modeCard(style)
                        }
                        Button {
                            selectAfterSave = true
                            editing = WritingStyle(title: "", prompt: "")
                        } label: {
                            Label("Add mode", systemImage: "plus")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(SaysoPressButtonStyle()).foregroundStyle(SaysoTheme.accent)
                        .background(SaysoTheme.accentSoft, in: .rect(cornerRadius: 18))
                        .accessibilityIdentifier("addModeButton")
                    }
                    if let error = styles.storageError { Text(error).font(.footnote).foregroundStyle(SaysoTheme.secondaryInk) }
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your original is always yours.", systemImage: "text.quote")
                            .font(.subheadline.weight(.medium)).foregroundStyle(SaysoTheme.ink)
                        Text("Rewrites use Apple Intelligence. You can return to your original transcript any time.")
                            .font(.footnote).foregroundStyle(SaysoTheme.secondaryInk).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                        if !intelligence.isAvailable {
                            Text(intelligence.availabilityMessage).font(.footnote).foregroundStyle(SaysoTheme.secondaryInk)
                        }
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(SaysoTheme.surface, in: .rect(cornerRadius: 20))
                }
                .padding(.horizontal, 20).padding(.bottom, 32)
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

    private func modeCard(_ style: WritingStyle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if style.mode == .custom && style.isBuiltIn {
                    selectAfterSave = true
                    editing = style
                } else {
                    selected = style.id
                    dismiss()
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: style.symbol)
                            .font(.title3.weight(.medium)).foregroundStyle(SaysoTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(SaysoTheme.accentSoft, in: .rect(cornerRadius: 14))
                            .accessibilityHidden(true)
                    }
                    Text(style.title).font(.headline).foregroundStyle(SaysoTheme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    Image(systemName: selected == style.id ? "checkmark.circle.fill" : "circle")
                        .font(.body).foregroundStyle(SaysoTheme.accent)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(SaysoPressButtonStyle()).accessibilityIdentifier("mode-\(style.id)")
            .accessibilityLabel(style.title)
            .accessibilityAddTraits(selected == style.id ? .isSelected : [])
            .accessibilityHint(style.mode == .custom && style.isBuiltIn ? "Opens your custom writing instructions" : "Use this mode for your next dictation")
            Text(style.isCustomized ? "Your custom take on \(style.title.lowercased())." : style.subtitle)
                .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                .lineLimit(style.isBuiltIn ? nil : 3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20).padding(.bottom, 16)
            if !style.isOriginal {
                HStack {
                    Button {
                        selectAfterSave = false
                        editing = style
                    } label: {
                        Label("Edit prompt", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.medium))
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(SaysoPressButtonStyle()).foregroundStyle(SaysoTheme.accent)
                    .accessibilityLabel("Edit \(style.title) prompt")
                    .accessibilityIdentifier("edit-mode-\(style.id)")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.bottom, 8)
            }
        }
        .background(selected == style.id ? SaysoTheme.accentSoft : SaysoTheme.paper, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(selected == style.id ? SaysoTheme.accent : SaysoTheme.hairline, lineWidth: selected == style.id ? 1.5 : 1)
                .accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : SaysoMotion.feedback, value: selected == style.id)
    }
}

/// Saved prompts are shared by recording and every Rewrite menu.
struct WritingModesSettingsView: View {
    let styles: WritingStyleStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editing: WritingStyle?

    var body: some View {
        Form {
            if !dynamicTypeSize.isAccessibilitySize {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "A little direction")
                        Text("Make every mode your own.")
                            .font(.system(.title2, design: .serif)).foregroundStyle(SaysoTheme.ink)
                        Text("Give Sayso a tone, a format, or a few simple rules. Your prompts shape future rewrites.")
                            .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, 8)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }
            Section {
                ForEach(styles.styles.filter { !$0.isOriginal }) { style in
                    Button { editing = style } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: style.symbol)
                                .foregroundStyle(SaysoTheme.accent).frame(width: 24, height: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(style.title).font(.headline).foregroundStyle(SaysoTheme.ink)
                                Text(style.isCustomized ? "Custom prompt" : style.isBuiltIn ? style.subtitle : "Your writing instructions")
                                    .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(SaysoTheme.secondaryInk)
                                .padding(.top, 6).accessibilityHidden(true)
                        }.frame(minHeight: 44).padding(.vertical, 8)
                    }.accessibilityIdentifier("edit-mode-\(style.id)")
                }
                Button { editing = WritingStyle(title: "", prompt: "") } label: {
                    Label("Add mode", systemImage: "plus.circle").font(.body.weight(.medium)).frame(minHeight: 44)
                }.accessibilityIdentifier("addModeButton")
            } header: { Text("Your writing modes").textCase(nil) } footer: {
                Text("Original always keeps your words untouched. Editing a prompt won’t change dictations you’ve already saved.")
            }.listRowBackground(SaysoTheme.paper)
            if let error = styles.storageError {
                Section { Text(error).font(.footnote).foregroundStyle(SaysoTheme.secondaryInk) }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                if !dynamicTypeSize.isAccessibilitySize {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Give your words a direction.")
                                .font(.system(.title2, design: .serif)).foregroundStyle(SaysoTheme.ink)
                            Text("A good prompt says how it should sound and what the result should look like.")
                                .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk).lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 8)
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                }
                if !style.isBuiltIn {
                    Section {
                        TextField("For example, Team update", text: $title)
                            .textInputAutocapitalization(.words).frame(minHeight: 44)
                            .accessibilityLabel("Mode name").accessibilityIdentifier("modeNameField")
                    } header: { Text("Name").textCase(nil) }
                    .listRowBackground(SaysoTheme.paper)
                }
                Section {
                    TextEditor(text: $prompt).font(.body).lineSpacing(5).frame(minHeight: 220)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel(isLegacyCustom ? "Custom style instructions" : "Rewrite prompt")
                        .accessibilityIdentifier(isLegacyCustom ? "customStyleInstructions" : "rewritePromptEditor")
                } header: { Text("Rewrite prompt").textCase(nil) } footer: {
                    if dynamicTypeSize.isAccessibilitySize {
                        Text("A good prompt says how it should sound and what the result should look like.")
                    }
                    Text("For example: Make this a short, friendly reply. Keep my wording and skip the greeting.\n\nSayso supplies the transcript. Your original always stays available.")
                }.listRowBackground(SaysoTheme.paper)
                if let builtIn = style.builtInMode, builtIn != .custom, builtIn != .transcript {
                    Section {
                        Button("Restore default prompt") { prompt = builtIn.instructions; error = nil }
                            .frame(minHeight: 44)
                            .disabled(prompt == builtIn.instructions)
                            .accessibilityIdentifier("resetModePromptButton")
                    }.listRowBackground(SaysoTheme.paper)
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                }
                if !style.isBuiltIn && !isNew {
                    Section {
                        Button("Delete mode", role: .destructive) { confirmingDelete = true }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("deleteModeButton")
                    } footer: { Text("Saved dictations keep their text and mode name when a mode is edited or deleted.") }
                    .listRowBackground(SaysoTheme.paper)
                }
            }
            .accessibilityIdentifier("writingStyleEditorForm")
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
        .presentationDetents([.large])
    }
}
