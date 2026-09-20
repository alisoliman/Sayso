import SwiftUI
import Speech
import UniformTypeIdentifiers

struct SettingsView: View {
    let intelligence: IntelligenceService
    let store: DictationStore
    let styles: WritingStyleStore
    @Bindable var speechModels: ParakeetModelStore
    var isDictationBusy = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("speechLocale") private var locale = SpeechLanguage.defaultIdentifier
    @AppStorage(SpeechProvider.preferenceKey) private var providerRaw = SpeechProvider.defaultProvider.rawValue
    @AppStorage("saveHistory") private var saveHistory = true
    @AppStorage("haptics") private var haptics = true
    @AppStorage("vocabulary") private var vocabulary = ""
    @State private var supportedLocales: Set<String>?
    @State private var confirmingDelete = false
    @State private var importingModel = false
    @State private var confirmingModelRemoval = false
    private var provider: SpeechProvider { SpeechProvider(rawValue: providerRaw) ?? .defaultProvider }

    var body: some View {
        NavigationStack {
            Form {
                if !dynamicTypeSize.isAccessibilitySize {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Eyebrow(text: "Your personal writing studio")
                            Text("Settle into your flow.")
                                .font(.system(.title2, design: .serif)).foregroundStyle(SaysoTheme.ink)
                            Label("Your voice stays on your iPhone.", systemImage: "lock.shield")
                                .font(.subheadline.weight(.medium)).foregroundStyle(SaysoTheme.accent)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Choose how Sayso listens, writes, and keeps your words.")
                                .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 8)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                }
                Section {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Speech model").font(.headline).foregroundStyle(SaysoTheme.ink)
                            Menu { providerPicker } label: { selectionLabel(provider.name) }
                                .accessibilityLabel("Speech model")
                                .accessibilityValue(provider.name)
                                .accessibilityIdentifier("speechProviderPicker")
                        }
                    } else { providerPicker }
                    if provider == .parakeet {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Parakeet TDT v3", systemImage: "waveform")
                                .font(.headline).foregroundStyle(SaysoTheme.ink)
                            Text(speechModels.status).font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("parakeetModelStatus")
                        if speechModels.isWorking {
                            HStack(alignment: .top, spacing: 12) {
                                ProgressView()
                                Text(speechModels.status).font(.subheadline)
                            }
                            Text("The download and initial model preparation can take a few minutes.")
                                .font(.footnote).foregroundStyle(SaysoTheme.secondaryInk)
                            Button("Cancel installation") { speechModels.cancel() }.frame(minHeight: 44)
                        } else {
                            if !speechModels.isInstalled {
                                Button("Download Parakeet (\(ParakeetModelFiles.downloadSizeDescription))") {
                                    speechModels.download()
                                }.frame(minHeight: 44).accessibilityIdentifier("downloadParakeetButton")
                            }
                            Button(speechModels.isInstalled ? "Replace from model folder…" : "Import model folder…") {
                                importingModel = true
                            }.frame(minHeight: 44).accessibilityIdentifier("importParakeetButton")
                            if speechModels.isInstalled {
                                Button("Remove model", role: .destructive) { confirmingModelRemoval = true }.frame(minHeight: 44)
                            }
                        }
                        if let error = speechModels.error {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Link("Parakeet by NVIDIA · Core ML by Fluid Inference", destination: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")!)
                            .font(.footnote).frame(minHeight: 44)
                    }
                    if provider == .apple {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Language").font(.headline).foregroundStyle(SaysoTheme.ink)
                                Menu { languagePicker } label: { selectionLabel(selectedLanguageName) }
                                    .accessibilityLabel("Language")
                                    .accessibilityValue(selectedLanguageName)
                                    .accessibilityIdentifier("languagePicker")
                            }
                        } else { languagePicker }
                    }
                } header: { Text("Listen").textCase(nil) } footer: {
                    if provider == .parakeet {
                        Text("Download once or import the Parakeet TDT v3 Core ML folder. Recording then works offline, without Apple Intelligence. Transcription appears after Stop; recordings are limited to 10 minutes. \(provider.languageDescription)")
                    } else {
                        Text("Apple’s on-device speech model provides live transcription. Language assets may need an initial download.")
                    }
                }
                .disabled(isDictationBusy)
                .listRowBackground(SaysoTheme.paper)
                Section {
                    NavigationLink {
                        Form {
                            if !dynamicTypeSize.isAccessibilitySize {
                                Section {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("The words you know best.")
                                            .font(.system(.title2, design: .serif)).foregroundStyle(SaysoTheme.ink)
                                        Text("Names, places, and terms that come up in your day.")
                                            .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }.padding(.vertical, 8)
                                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                            }
                            Section {
                                TextEditor(text: $vocabulary)
                                    .font(.body).lineSpacing(5).frame(minHeight: 260).autocorrectionDisabled()
                                    .scrollContentBackground(.hidden)
                                    .accessibilityLabel("Vocabulary, one word or phrase per line")
                            } header: { Text("One word or phrase per line").textCase(nil) } footer: {
                                if dynamicTypeSize.isAccessibilitySize {
                                    Text("Add names, places, and terms that come up in your day.")
                                }
                                Text("These give Apple Speech and rewriting a little context. Parakeet transcription does not use this vocabulary. Spelling is still worth checking.")
                            }
                            .listRowBackground(SaysoTheme.paper)
                        }
                        .scrollContentBackground(.hidden).background(SaysoTheme.canvas)
                        .navigationTitle("Vocabulary").navigationBarTitleDisplayMode(.inline)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Vocabulary", systemImage: "text.book.closed")
                                .foregroundStyle(SaysoTheme.ink)
                            Text("\(vocabulary.split(separator: "\n").count) saved words and phrases")
                                .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                        }.padding(.vertical, 4)
                    }
                    Toggle(isOn: $haptics) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Haptic feedback").foregroundStyle(SaysoTheme.ink)
                            Text("A little nudge when you start and stop.")
                                .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 4)
                    }
                } header: { Text("Make it familiar").textCase(nil) }
                .listRowBackground(SaysoTheme.paper)
                Section {
                    NavigationLink { WritingModesSettingsView(styles: styles) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Writing modes", systemImage: "slider.horizontal.3")
                                .foregroundStyle(SaysoTheme.ink)
                            Text("Tune a prompt or create your own style.")
                                .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("writingModesSettingsButton")
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Apple Intelligence", systemImage: "sparkles")
                            .font(.headline).foregroundStyle(SaysoTheme.accent)
                        Text(intelligence.availabilityMessage)
                            .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, 8)
                } header: { Text("Write").textCase(nil) } footer: {
                    Text("Rewriting is optional. Original needs only your selected speech model. Sayso doesn’t send your audio or text to a server.")
                }
                .listRowBackground(SaysoTheme.paper)
                Section {
                    Toggle(isOn: $saveHistory) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Save history").foregroundStyle(SaysoTheme.ink)
                            Text("Keep new dictations for another day.")
                                .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("saveHistoryToggle")
                    if !store.entries.isEmpty {
                        Button("Delete all dictations", role: .destructive) { confirmingDelete = true }.frame(minHeight: 44)
                    }
                } header: { Text("Keep").textCase(nil) } footer: {
                    Text("History is stored in Sayso on this iPhone and may be included in your device backup. Turning this off affects new dictations. Existing history stays until you delete it. Audio is not saved.")
                }
                .listRowBackground(SaysoTheme.paper)
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Start dictation", systemImage: "waveform")
                            .font(.headline).foregroundStyle(SaysoTheme.accent)
                        Text("In Shortcuts, add Sayso’s Start Dictation action. Assign that shortcut to your Action button for quick access.")
                            .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, 8)
                } header: { Text("One press away").textCase(nil) }
                .listRowBackground(SaysoTheme.accentSoft)
                Section {
                    LabeledContent {
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                            .foregroundStyle(SaysoTheme.secondaryInk)
                    } label: {
                        Text("Sayso").font(.headline).foregroundStyle(SaysoTheme.ink)
                    }
                } footer: { Text("A little less typing. A little more you.") }
                .listRowBackground(SaysoTheme.paper)
            }
            .accessibilityIdentifier("settingsForm")
            .scrollContentBackground(.hidden).background(SaysoTheme.canvas)
            .tint(SaysoTheme.accent)
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
                Button("Delete all dictations", role: .destructive) { store.deleteAll() }
            } message: { Text("This permanently removes \(store.entries.count) saved dictations and their original transcripts from this iPhone.") }
            .task {
                speechModels.refresh()
                intelligence.refreshAvailability()
                supportedLocales = Set(await SpeechTranscriber.supportedLocales.map { $0.identifier.replacingOccurrences(of: "_", with: "-") })
            }
        }
    }

    private var providerPicker: some View {
        Picker("Speech model", selection: $providerRaw) {
            ForEach(SpeechProvider.allCases) { option in
                Text(option.name).tag(option.rawValue)
            }
        }
        .accessibilityIdentifier("speechProviderPicker")
    }

    private func selectionLabel(_ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(value)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(.body).accessibilityHidden(true)
        }
        .foregroundStyle(SaysoTheme.accent)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    private var selectedLanguageName: String {
        let name = SpeechLanguage.choices.first { $0.id == locale }?.name ?? locale
        return name + (supportedLocales?.contains(locale) == false ? " · unavailable" : "")
    }

    private var languagePicker: some View {
        Picker("Language", selection: $locale) {
            ForEach(SpeechLanguage.choices, id: \.id) { choice in
                Text(choice.name + (supportedLocales?.contains(choice.id) == false ? " · unavailable" : "")).tag(choice.id)
            }
        }
        .accessibilityIdentifier("languagePicker")
    }

}
