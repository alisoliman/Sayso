import SwiftUI

struct ModePickerView: View {
    @Binding var selected: String
    @Binding var instructions: String
    let intelligence: IntelligenceService
    @Environment(\.dismiss) private var dismiss
    @State private var showCustom = false
    @State private var customDraft = ""
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 31.0
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Make it sound like you.").font(.system(size: titleSize, weight: .medium, design: .serif)).tracking(-0.8)
                        Text("Choose how your words take shape.")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }.padding(.top, 20)
                    VStack(spacing: 2) {
                        ForEach(WritingMode.allCases) { mode in
                            Button {
                                if mode == .custom {
                                    customDraft = instructions
                                    showCustom = true
                                } else {
                                    selected = mode.rawValue
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: mode.symbol).font(.system(size: 21, weight: .regular))
                                        .foregroundStyle(selected == mode.rawValue ? SaysoTheme.accent : .secondary)
                                        .frame(width: 42, height: 48)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(mode.title).font(.headline).foregroundStyle(.primary)
                                        Text(mode.subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 8)
                                    if selected == mode.rawValue {
                                        Image(systemName: "checkmark.circle.fill").font(.system(size: 21)).foregroundStyle(SaysoTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected == mode.rawValue ? SaysoTheme.accent.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 20))
                                .contentShape(.rect)
                            }.buttonStyle(.plain).accessibilityIdentifier("mode-\(mode.rawValue)")
                                .accessibilityAddTraits(selected == mode.rawValue ? .isSelected : [])
                        }
                    }
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
            .sheet(isPresented: $showCustom) {
                CustomStyleEditor(draft: $customDraft) { editedInstructions in
                    instructions = editedInstructions
                    selected = WritingMode.custom.rawValue
                    showCustom = false
                    dismiss()
                }
            }
        }
    }
}

private struct CustomStyleEditor: View {
    @Binding var draft: String
    let onSave: (String) -> Void

    var body: some View {
        // Reading the binding in this body keeps the editor and toolbar on the
        // same live draft when a saved style is loaded before sheet presentation.
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $draft).frame(minHeight: 160)
                        .accessibilityLabel("Custom style instructions")
                        .accessibilityIdentifier("customStyleInstructions")
                } header: { Text("Your writing style") } footer: {
                    Text("For example: Make this a short, friendly reply. Keep my wording and skip the greeting. Custom instructions change the style of a transcript.")
                }
            }
            .navigationTitle("Custom mode").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(draft) }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveCustomStyleButton")
                }
            }
        }.presentationDetents([.medium, .large])
    }
}
