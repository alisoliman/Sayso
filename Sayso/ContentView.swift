import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: DictationController
    let styles: WritingStyleStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("writingMode") private var modeRaw = WritingMode.transcript.rawValue
    @AppStorage("speechLocale") private var locale = SpeechLanguage.defaultIdentifier
    @AppStorage(SpeechProvider.preferenceKey) private var providerRaw = SpeechProvider.defaultProvider.rawValue
    @AppStorage("vocabulary") private var vocabulary = ""
    @AppStorage("saveHistory") private var saveHistory = true
    @ScaledMetric(relativeTo: .largeTitle) private var idleTitleSize = 38.0
    @ScaledMetric(relativeTo: .title) private var writingSize = 26.0
    @State private var sheet: HomeSheet?
    @State private var importing = false
    @State private var showOriginal = false
    @State private var editText = ""
    @State private var discardRecording = false
    @State private var followingLiveTranscript = true
    private var mode: WritingStyle { styles.style(for: modeRaw) }
    private var recording: Bool { model.phase == .recording }
    private var compactHeight: Bool { verticalSizeClass == .compact }

    private struct PreparationKey: Equatable {
        let isActive: Bool
        let isIdle: Bool
        let provider: String
        let locale: String
        let vocabulary: String
        let mode: String
        let modelInstalled: Bool
        let modelInstalling: Bool
        let modelRevision: UUID
    }

    private var preparationKey: PreparationKey {
        PreparationKey(isActive: scenePhase == .active, isIdle: !model.isBusy,
                       provider: providerRaw, locale: locale, vocabulary: vocabulary,
                       mode: mode.mode.rawValue, modelInstalled: model.speechModels.isInstalled,
                       modelInstalling: model.speechModels.isWorking, modelRevision: model.speechModels.installationRevision)
    }

    private var progressMessage: String {
        switch model.phase {
        case .refining: "A little polish…"
        case .finishing: "Finishing your thought…"
        default: "Getting ready…"
        }
    }

    enum HomeSheet: String, Identifiable {
        case history, settings, modes, edit
        var id: String { rawValue }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: compactHeight ? 16 : 24) {
                            if let error = model.store.storageError { information(error, symbol: "externaldrive.badge.exclamationmark") }
                            if let result = model.current, model.phase != .recording {
                                resultContent(result)
                            } else if recording || model.phase == .finishing {
                                liveContent
                            } else {
                                idleContent
                                    .frame(minHeight: compactHeight ? 0 : (dynamicTypeSize.isAccessibilitySize ? 260 : max(260, geometry.size.height - 295)))
                            }
                        }
                        .id("transcriptContent")
                        .padding(.horizontal, 28)
                        .padding(.top, model.current != nil || recording || model.phase == .finishing ? (compactHeight ? 12 : 34) : 0)
                        .padding(.bottom, compactHeight ? 12 : 28)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("transcriptScrollView")
                    .defaultScrollAnchor(.top, for: .alignment)
                    .scrollIndicators(.hidden)
                    .onScrollPhaseChange { oldPhase, newPhase, context in
                        guard recording else { return }
                        if newPhase == .tracking || newPhase == .interacting { followingLiveTranscript = false }
                        if newPhase == .idle, oldPhase != .animating {
                            followingLiveTranscript = context.geometry.visibleRect.maxY >= context.geometry.contentSize.height - 60
                        }
                    }
                    .onChange(of: model.speech.partialText) { _, _ in
                        if recording && followingLiveTranscript {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { reader.scrollTo("transcriptContent", anchor: .bottom) }
                        }
                    }
                    .onChange(of: model.phase) { _, phase in
                        if phase == .recording { followingLiveTranscript = true }
                        if phase == .idle { reader.scrollTo("transcriptContent", anchor: .top) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if recording && !followingLiveTranscript {
                            Button {
                                followingLiveTranscript = true
                                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { reader.scrollTo("transcriptContent", anchor: .bottom) }
                            } label: {
                                Label("Latest words", systemImage: "arrow.down")
                                    .font(.subheadline.weight(.medium)).padding(6)
                            }
                            .buttonStyle(.glass).padding(compactHeight ? 12 : 20)
                            .accessibilityIdentifier("latestWordsButton")
                        }
                    }
                }
                if compactHeight { compactControls }
                else { controls }
            }
            .background { QuietBackground() }
        }
        .sheet(item: $sheet) { active in
            switch active {
            case .history:
                HistoryView(store: model.store, styles: styles) { id, selected in
                    showOriginal = false
                    sheet = nil
                    model.reworkSaved(id, mode: selected.mode, instructions: selected.prompt, vocabulary: vocabulary, writingStyle: selected)
                }
            case .settings: SettingsView(intelligence: model.intelligence, store: model.store, styles: styles,
                                         speechModels: model.speechModels, isDictationBusy: model.isBusy)
            case .modes:
                ModePickerView(selected: $modeRaw, styles: styles, intelligence: model.intelligence)
                    .presentationDetents([.large])
            case .edit:
                DictationTextEditor(text: $editText, onCancel: { sheet = nil }) { editedText in
                    model.updateText(editedText)
                    sheet = nil
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.importAudio(url, mode: mode.mode, locale: locale, instructions: mode.prompt, vocabulary: vocabulary, saveHistory: saveHistory, writingStyle: mode) }
            case .failure(let error): model.notice = error.localizedDescription
            }
        }
        .alert("Couldn’t complete dictation", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
            if let report = model.speech.diagnosticsReport {
                Button("Copy diagnostics") {
                    UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: report]], options: [.localOnly: true])
                }
            }
            if model.notice == ParakeetModelStore.ModelError.notInstalled.errorDescription {
                Button("Set up speech") { model.notice = nil; sheet = .settings }
            } else if model.notice?.localizedCaseInsensitiveContains("settings") == true {
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
        } message: { Text(model.notice ?? "") }
        .confirmationDialog("Discard this recording?", isPresented: $discardRecording, titleVisibility: .visible) {
            Button("Discard recording", role: .destructive) { model.cancel() }
            Button("Keep recording", role: .cancel) { }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.appDidEnterBackground() }
            if phase == .active {
                model.intelligence.refreshAvailability()
                try? KeyboardHandoff().purgeExpired()
                consumeRoute()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            model.appDidReceiveMemoryWarning()
        }
        .onChange(of: AppRoute.shared.recordRequest) { _, _ in consumeRoute() }
        .onOpenURL { url in
            guard url.scheme == "sayso" else { return }
            if url.host == "record" { AppRoute.shared.requestRecording() }
            if url.host == "keyboard" { AppRoute.shared.requestRecording(destination: .keyboard) }
            // sayso://recording from a Live Activity opens the current session.
            consumeRoute()
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: model.phase)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: model.current?.id)
        .task {
            model.intelligence.refreshAvailability()
            try? KeyboardHandoff().purgeExpired()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--preview-result") { model.loadPreviewResult() }
            #endif
            consumeRoute()
        }
        .task(id: preparationKey) {
            guard scenePhase == .active, !model.isBusy else { return }
            model.prepareForRecording(locale: locale, vocabulary: vocabulary, mode: mode.mode)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 7) {
                Image(systemName: "waveform").font(.system(size: 20, weight: .medium)).foregroundStyle(SaysoTheme.accent)
                Text("sayso").font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-1.4)
            }.accessibilityElement(children: .combine).accessibilityLabel("Sayso")
            Spacer()
            HStack(spacing: 10) {
                RoundButton(symbol: "clock", label: "History") { sheet = .history }.accessibilityIdentifier("historyButton")
                RoundButton(symbol: "slider.horizontal.3", label: "Settings") { sheet = .settings }.accessibilityIdentifier("settingsButton")
            }.disabled(model.isBusy)
        }.padding(.horizontal, 26).padding(.top, compactHeight ? 4 : 12).padding(.bottom, compactHeight ? 4 : 12)
    }

    @ViewBuilder
    private var idleContent: some View {
        if compactHeight {
            VStack(spacing: 8) {
                HStack(spacing: 18) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        WaveformView(recording: false, level: 0).frame(width: 160, height: 42)
                    }
                    Text("Speak freely.")
                        .font(.system(size: idleTitleSize, weight: .medium, design: .serif)).tracking(-1.3)
                        .multilineTextAlignment(.center)
                }
                Button { importing = true } label: {
                    Label("Import audio", systemImage: "arrow.down.doc")
                        .font(.subheadline.weight(.medium))
                        .padding(.vertical, 8).padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .foregroundStyle(.secondary).buttonStyle(.plain)
                .accessibilityIdentifier("importButton")
                .disabled(model.isBusy)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 30)
                if !dynamicTypeSize.isAccessibilitySize {
                    WaveformView(recording: false, level: 0)
                        .frame(width: 250, height: 116)
                        .padding(.bottom, 38)
                }
                Text("Speak freely.")
                    .font(.system(size: idleTitleSize, weight: .medium, design: .serif)).tracking(-1.3)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 46)
                Button { importing = true } label: {
                    Label("Import audio", systemImage: "arrow.down.doc")
                        .font(.system(size: 14, weight: .medium)).padding(.vertical, 10).padding(.horizontal, 16)
                }
                .foregroundStyle(.secondary).buttonStyle(.plain)
                .accessibilityIdentifier("importButton")
                .disabled(model.isBusy)
                .padding(.bottom, 22)
            }.frame(maxWidth: .infinity)
        }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: compactHeight ? 12 : 26) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(SaysoTheme.accent).frame(width: 6, height: 6)
                    Eyebrow(text: model.phase == .finishing ? "Finishing" : "Listening")
                }
                Spacer()
                if let start = model.startedAt {
                    Group {
                        if recording { Text(start, style: .timer) }
                        else {
                            let seconds = Int(model.elapsedRecordingTime)
                            Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                        }
                    }
                    .monospacedDigit().font(.system(size: 13)).foregroundStyle(.secondary)
                    .accessibilityLabel("Recording duration")
                }
            }
            if model.destination == .keyboard {
                information("Return to your app and choose Sayso. Tap Stop & insert to add your words at the cursor.", symbol: "keyboard")
            }
            Text(model.speech.partialText.isEmpty
                 ? (recording ? "I’m listening…" : "Finishing your words…")
                 : model.speech.partialText)
                .font(.system(size: writingSize, weight: .regular, design: .serif)).lineSpacing(8)
                .foregroundStyle(model.speech.partialText.isEmpty ? .secondary : .primary)
                .contentTransition(.opacity)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("liveTranscript")
            WaveformView(recording: recording, level: model.speech.level)
                .frame(height: compactHeight ? 20 : 60).padding(.top, compactHeight ? 6 : 24)
        }
    }

    private func resultContent(_ entry: Dictation) -> some View {
        let actions = dynamicTypeSize >= .xLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: compactHeight ? 16 : 25) {
            HStack {
                Eyebrow(text: model.phase == .refining ? "Refining your words" : "Ready to use")
                Spacer()
                Text("\(entry.wordCount) words").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            Text(showOriginal ? entry.original : entry.text)
                .font(.system(size: writingSize, weight: .regular, design: .serif)).lineSpacing(9)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("resultText")
            if let note = model.resultNote { information(note, symbol: "info.circle") }
            actions {
                Button { model.copy(showOriginal ? entry.original : entry.text) } label: {
                    Label(model.copied ? "Copied" : "Copy", systemImage: model.copied ? "checkmark" : "document.on.document")
                        .font(.subheadline.weight(.medium)).foregroundStyle(SaysoTheme.onAccent).fixedSize().padding(.horizontal, 4).padding(.vertical, 7)
                }.buttonStyle(.glassProminent).buttonBorderShape(.capsule).accessibilityIdentifier("copyButton")
                ShareLink(item: showOriginal ? entry.original : entry.text) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 18)).frame(width: 42, height: 42)
                }.buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Share text")
                Button { editText = entry.text; sheet = .edit } label: {
                    Image(systemName: "pencil").font(.system(size: 18)).frame(width: 42, height: 42)
                }.buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Edit text").accessibilityIdentifier("editButton")
                KeyboardSendButton(text: showOriginal ? entry.original : entry.text, id: entry.id)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            }.disabled(model.isBusy)
            HStack {
                if entry.original != entry.text {
                    Button(showOriginal ? "Show refined" : "Show original") { showOriginal.toggle() }
                        .accessibilityIdentifier("originalButton")
                }
                Spacer()
                Menu {
                    ForEach(styles.styles) { option in
                        Button { showOriginal = false; model.rework(mode: option.mode, instructions: option.prompt, vocabulary: vocabulary, writingStyle: option) } label: {
                            Label(option.title, systemImage: option.symbol)
                        }
                        .disabled(option.mode != .transcript && option.prompt.isEmpty)
                        .accessibilityIdentifier("rewrite-\(option.id)")
                    }
                    Divider()
                    Button("Edit prompts & modes", systemImage: "slider.horizontal.3") { sheet = .modes }
                } label: { Label("Rewrite", systemImage: "sparkles") }
                    .accessibilityIdentifier("rewriteButton")
            }.font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).disabled(model.isBusy)
            Button { importing = true } label: {
                Label("Import audio", systemImage: "arrow.down.doc")
                    .font(.system(size: 14, weight: .medium)).padding(.vertical, 10)
            }
            .foregroundStyle(.secondary).buttonStyle(.plain)
            .accessibilityIdentifier("importButton").disabled(model.isBusy)
        }
    }

    private var controls: some View {
        VStack(spacing: 18) {
            if !model.isBusy {
                Button { startRecording(destination: .keyboard) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "keyboard").font(.system(size: 17, weight: .medium))
                        Text(dynamicTypeSize.isAccessibilitySize ? "Other apps" : "Dictate in another app")
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, 7).padding(.horizontal, 12)
                }
                .buttonStyle(.glass).buttonBorderShape(.capsule)
                .accessibilityLabel("Dictate in another app")
                .accessibilityIdentifier("keyboardRecordButton")
                .accessibilityHint("Starts a recording you can continue after returning to your app")
            }
            if model.phase == .preparing || model.phase == .finishing || model.phase == .refining {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(progressMessage)
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .lineLimit(3)
                    Button("Cancel") { model.cancel() }.font(.system(size: 13, weight: .medium)).disabled(!model.canCancel)
                }.padding(.horizontal, 20)
            }
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) {
                        modeControl
                        recordControl
                    }
                    .padding(16)
                    .glassEffect(.regular, in: .rect(cornerRadius: 32))
                } else {
                    HStack(spacing: 16) {
                        modeControl
                        recordControl
                    }
                    .padding(10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 40))
                }
            }
            .frame(maxWidth: 410)
            if recording {
                Button("Discard recording") { discardRecording = true }.foregroundStyle(.secondary)
                    .accessibilityIdentifier("discardRecordingButton")
                    .font(.system(size: 11, weight: .medium))
                    .frame(minHeight: 24)
            }
        }
        .padding(.horizontal, 24).padding(.top, 15).padding(.bottom, 16)
        .background { LinearGradient(colors: [.clear, SaysoTheme.canvas, SaysoTheme.canvas], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom) }
    }

    private var compactControls: some View {
        VStack(spacing: 6) {
            if model.phase == .preparing || model.phase == .finishing || model.phase == .refining {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progressMessage)
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            HStack(spacing: 12) {
                modeControl
                if recording {
                    Button { discardRecording = true } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(.secondary).buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityLabel("Discard recording")
                    .accessibilityIdentifier("discardRecordingButton")
                } else if model.isBusy {
                    Button("Cancel") { model.cancel() }
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                        .disabled(!model.canCancel)
                } else {
                    Button { startRecording(destination: .keyboard) } label: {
                        Image(systemName: "keyboard").font(.system(size: 20, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityLabel("Dictate in another app")
                    .accessibilityIdentifier("keyboardRecordButton")
                    .accessibilityHint("Starts a recording you can continue after returning to your app")
                }
                recordControl
            }
            .padding(8)
            .glassEffect(.regular, in: .rect(cornerRadius: 40))
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 24).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background { LinearGradient(colors: [.clear, SaysoTheme.canvas, SaysoTheme.canvas], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom) }
    }

    private var modeControl: some View {
        Button { sheet = .modes } label: {
            HStack(spacing: 9) {
                Image(systemName: mode.symbol).font(.system(size: 16))
                Text(mode.title)
                    .font(dynamicTypeSize.isAccessibilitySize ? .headline : .subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary).padding(.leading, 9)
            .frame(maxWidth: .infinity, minHeight: compactHeight ? 44 : 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain).disabled(model.isBusy).accessibilityIdentifier("modeButton")
        .accessibilityHint("Choose a dictation mode")
    }

    private var recordControl: some View {
        Button {
            if recording { model.finish() } else { startRecording() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: recording ? 23 : 26, weight: .medium))
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                if !compactHeight {
                    Text(recording ? "Stop" : "Record").font(.headline)
                }
            }
            .foregroundStyle(SaysoTheme.onAccent)
            .padding(.horizontal, compactHeight ? 0 : 18)
            .frame(width: compactHeight ? 56 : nil, height: compactHeight ? 56 : nil)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize && !compactHeight ? .infinity : nil, minHeight: compactHeight ? 56 : 64)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(compactHeight ? .circle : .capsule)
        .disabled(model.isBusy && !recording)
        .accessibilityLabel(recording ? "Stop recording" : "Start recording")
        .accessibilityHint(recording ? "Finish and prepare your text" : "Turn your voice into text")
        .accessibilityIdentifier("recordButton")
    }

    private func information(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.footnote).foregroundStyle(.primary).lineSpacing(3)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }
    private func startRecording(destination: DictationController.Destination = .app) {
        showOriginal = false
        model.start(mode: mode.mode, locale: locale, instructions: mode.prompt, vocabulary: vocabulary, saveHistory: saveHistory, destination: destination, writingStyle: mode)
    }
    private func consumeRoute() {
        guard scenePhase == .active, let request = AppRoute.shared.recordRequest else { return }
        AppRoute.shared.recordRequest = nil
        if !model.isBusy { sheet = nil; startRecording(destination: request.destination) }
    }
}

private struct DictationTextEditor: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    var body: some View {
        // The toolbar reads the same live binding as the editor, including the
        // saved text assigned immediately before presenting this sheet.
        NavigationStack {
            TextEditor(text: $text)
                .font(.system(size: 21))
                .padding(.horizontal, 20)
                .padding(.vertical, verticalSizeClass == .compact ? 8 : 20)
                .scrollContentBackground(.hidden)
                .background(SaysoTheme.canvas)
                .accessibilityIdentifier("editText")
                .navigationTitle("Edit text").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { onSave(text) }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("saveEditButton")
                    }
                }
        }
    }
}

#Preview {
    ContentView(model: DictationController(store: DictationStore(fileURL: URL.temporaryDirectory.appending(path: "sayso-preview.json"))), styles: WritingStyleStore(defaults: UserDefaults(suiteName: "Sayso.Preview")!))
}
