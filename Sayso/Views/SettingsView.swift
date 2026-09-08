import SwiftUI
import Speech
import UniformTypeIdentifiers

struct SettingsView: View {
    let intelligence: IntelligenceService
    let store: DictationStore
    @Bindable var speechModels: ParakeetModelStore
    var isDictationBusy = false
    @Environment(\.dismiss) private var dismiss
    @AppStorage("speechLocale") private var locale = SpeechLanguage.defaultIdentifier
    @AppStorage(SpeechProvider.preferenceKey) private var providerRaw = SpeechProvider.defaultProvider.rawValue
    @AppStorage("saveHistory") private var saveHistory = true
    @AppStorage("haptics") private var haptics = true
    @AppStorage("vocabulary") private var vocabulary = ""
    @State private var supportedLocales: Set<String> = []
    @State private var loadedLanguages = false
    @State private var confirmingDelete = false
    @State private var sharingError: String?
    @State private var importingModel = false
    @State private var confirmingModelRemoval = false
    private var provider: SpeechProvider { SpeechProvider(rawValue: providerRaw) ?? .defaultProvider }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Speech model", selection: $providerRaw) {
                        ForEach(SpeechProvider.allCases) { option in
                            Text(option.name).tag(option.rawValue)
                        }
                    }.accessibilityIdentifier("speechProviderPicker")
                    if provider == .parakeet {
                        LabeledContent("Parakeet TDT v3", value: speechModels.status)
                            .accessibilityIdentifier("parakeetModelStatus")
                        if speechModels.isWorking {
                            HStack {
                                ProgressView()
                                Text(speechModels.status).font(.footnote)
                            }
                            Text("The download and initial model preparation can take a few minutes.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Cancel installation") { speechModels.cancel() }
                        } else {
                            if !speechModels.isInstalled {
                                Button("Download Parakeet (\(ParakeetModelFiles.downloadSizeDescription))") {
                                    speechModels.download()
                                }.accessibilityIdentifier("downloadParakeetButton")
                            }
                            Button(speechModels.isInstalled ? "Replace from model folder…" : "Import model folder…") {
                                importingModel = true
                            }.accessibilityIdentifier("importParakeetButton")
                            if speechModels.isInstalled {
                                Button("Remove model", role: .destructive) { confirmingModelRemoval = true }
                            }
                        }
                        if let error = speechModels.error {
                            Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                        }
                        Link("Parakeet by NVIDIA · Core ML by Fluid Inference", destination: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")!)
                            .font(.footnote)
                    }
                } header: { Text("Transcription") } footer: {
                    if provider == .parakeet {
                        Text("Download once or import the Parakeet TDT v3 Core ML folder. Recording and audio imports then work offline, without Apple Intelligence. Transcription appears after Stop; recordings and imports are limited to 10 minutes. \(provider.languageDescription)")
                    } else {
                        Text("Apple’s on-device speech model provides live transcription. Language assets may need an initial download.")
                    }
                }
                .disabled(isDictationBusy)
                Section {
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: "sparkles").foregroundStyle(SaysoTheme.accent).font(.system(size: 23)).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Apple Intelligence").font(.headline.weight(.medium))
                            Text(intelligence.availabilityMessage).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(.vertical, 5)
                } header: { Text("On this iPhone") } footer: {
                    Text("Optional writing styles use Apple Intelligence. Original needs only the selected speech model. Sayso doesn’t send your audio or text to a server.")
                }
                Section {
                    if provider == .apple {
                    Picker("Language", selection: $locale) {
                        ForEach(SpeechLanguage.choices, id: \.id) { choice in
                            Text(choice.name + (loadedLanguages && !isSupported(choice.id) ? " · unavailable" : "")).tag(choice.id)
                        }
                    }.accessibilityIdentifier("languagePicker")
                    }
                    NavigationLink {
                        Form {
                            Section {
                                TextEditor(text: $vocabulary).frame(minHeight: 220).autocorrectionDisabled()
                                    .accessibilityLabel("Vocabulary, one word or phrase per line")
                            } footer: { Text("Add names, places, and words you use often, one per line. These give Apple Speech and rewriting a little context. Parakeet transcription does not use this vocabulary. Spelling is still worth checking.") }
                        }
                        .navigationTitle("Vocabulary").navigationBarTitleDisplayMode(.inline)
                    } label: { LabeledContent("Vocabulary", value: "\(vocabulary.split(separator: "\n").count) words") }
                    Toggle("Haptic feedback", isOn: $haptics)
                } header: { Text("Dictation") }
                Section {
                    Toggle("Save history", isOn: $saveHistory).accessibilityIdentifier("saveHistoryToggle")
                    if !store.entries.isEmpty {
                        Button("Delete all dictations", role: .destructive) { confirmingDelete = true }
                    }
                } header: { Text("Your words") } footer: {
                    Text("History is stored in Sayso on this iPhone and may be included in your device backup. Turning this off affects new dictations. Existing history stays until you delete it. Audio is not saved.")
                }
                Section {
                    NavigationLink { KeyboardSetupView() } label: {
                        Label("Sayso keyboard", systemImage: "keyboard")
                    }
                    Label("Start dictation", systemImage: "waveform")
                    Text("In Shortcuts, add Sayso’s Start Dictation action. Assign that shortcut to your Action button for quick access.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("One press away") }
                Section {
                    HStack { Text("Sayso").font(.system(size: 19, weight: .semibold, design: .rounded)); Spacer(); Text("1.0").foregroundStyle(.secondary) }
                } footer: { Text("Made for a little less typing.") }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $importingModel, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url): speechModels.importFolder(url)
                case .failure(let error): speechModels.error = error.localizedDescription
                }
            }
            .confirmationDialog("Remove the local Parakeet model?", isPresented: $confirmingModelRemoval, titleVisibility: .visible) {
                Button("Remove model", role: .destructive) { speechModels.remove() }
            } message: { Text("You’ll need to download or import it again before using Parakeet. Your dictation history stays on this iPhone.") }
            .confirmationDialog("Delete all dictations?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete all dictations", role: .destructive) {
                    if store.deleteAll() {
                        do { try KeyboardHandoff().clear() }
                        catch KeyboardHandoff.HandoffError.unavailable { }
                        catch { sharingError = "History was deleted, but the shared keyboard copy couldn’t be cleared. " + error.localizedDescription }
                    }
                }
            } message: { Text("This permanently removes \(store.entries.count) saved dictations and their original transcripts from this iPhone.") }
            .alert("Keyboard sharing", isPresented: Binding(get: { sharingError != nil }, set: { if !$0 { sharingError = nil } })) {
                Button("OK") { sharingError = nil }
            } message: { Text(sharingError ?? "") }
            .task {
                speechModels.refresh()
                intelligence.refreshAvailability()
                supportedLocales = Set(await SpeechTranscriber.supportedLocales.map { $0.identifier.replacingOccurrences(of: "_", with: "-") })
                loadedLanguages = true
            }
        }
    }
    private func isSupported(_ id: String) -> Bool { supportedLocales.contains(id) }
}
