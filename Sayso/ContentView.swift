import SwiftUI

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
    @ScaledMetric(relativeTo: .title) private var writingSize = 23.0
    @State private var sheet: HomeSheet?
    @State private var showOriginal = false
    @State private var editText = ""
    @State private var discardRecording = false
    @State private var followingLiveTranscript = true
    private var mode: WritingStyle { styles.style(for: modeRaw) }
    private var recording: Bool { model.phase == .recording }
    private var compactHeight: Bool { verticalSizeClass == .compact }
    // Finishing keeps the live view in place; refining keeps the result in
    // place. Only changing the reading surface gets an entrance transition.
    private var contentStage: Int {
        if model.current != nil && !recording { return 2 }
        if recording || model.phase == .finishing { return 1 }
        return 0
    }

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
        case history, recent, settings, modes, edit
        var id: String { rawValue }
    }

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                header
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: compactHeight ? 16 : 24) {
                            if let error = model.store.storageError { information(error, symbol: "externaldrive.badge.exclamationmark") }
                            if let result = model.current, model.phase != .recording {
                                resultContent(result)
                                    .transition(SaysoMotion.content(reduceMotion: reduceMotion))
                            } else if recording || model.phase == .finishing {
                                liveContent
                                    .transition(SaysoMotion.content(reduceMotion: reduceMotion))
                            } else {
                                WritingHomeView(recentEntry: model.store.entries.first,
                                                onHistory: { sheet = .history }, onRecent: { sheet = .recent })
                                    .disabled(model.isBusy)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(SaysoMotion.content(reduceMotion: reduceMotion))
                            }
                        }
                        .id("transcriptContent")
                        .padding(.horizontal, 24)
                        .padding(.top, compactHeight ? 12 : 24)
                        .padding(.bottom, compactHeight ? 12 : 28)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                        .animation(reduceMotion ? nil : SaysoMotion.stateChange, value: contentStage)
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
                            withAnimation(reduceMotion ? nil : SaysoMotion.feedback) { reader.scrollTo("transcriptContent", anchor: .bottom) }
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
                            .transition(reduceMotion ? .identity : .opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : SaysoMotion.feedback, value: followingLiveTranscript)
                }
                if compactHeight { compactControls }
                else { controls }
            }
            .foregroundStyle(SaysoTheme.ink)
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
            case .recent:
                if let entry = model.store.entries.first {
                    NavigationStack {
                        HistoryDetailView(entry: entry, store: model.store, styles: styles) { id, selected in
                            showOriginal = false
                            sheet = nil
                            model.reworkSaved(id, mode: selected.mode, instructions: selected.prompt, vocabulary: vocabulary, writingStyle: selected)
                        }
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } }
                        }
                    }
                }
            case .settings: SettingsView(intelligence: model.intelligence, store: model.store, styles: styles,
                                         speechModels: model.speechModels, isDictationBusy: model.isBusy)
            case .modes:
                ModePickerView(selected: $modeRaw, styles: styles, intelligence: model.intelligence)
                    .presentationDetents([.large])
            case .edit:
                DictationTextEditor(text: $editText, onCancel: { sheet = nil }) { editedText in
                    model.updateText(editedText)
                    showOriginal = false
                    sheet = nil
                }
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
            consumeRoute()
        }
        .task {
            model.intelligence.refreshAvailability()
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
                VoiceEmblem().frame(width: 22, height: 22)
                Text("sayso").font(.system(.title2, design: .rounded, weight: .semibold)).tracking(-1)
            }.accessibilityElement(children: .combine).accessibilityLabel("Sayso")
            Spacer()
            HStack(spacing: 10) {
                RoundButton(symbol: "clock", label: "History") { sheet = .history }.accessibilityIdentifier("historyButton")
                RoundButton(symbol: "slider.horizontal.3", label: "Settings") { sheet = .settings }.accessibilityIdentifier("settingsButton")
            }.disabled(model.isBusy)
        }.padding(.horizontal, 26).padding(.top, compactHeight ? 4 : 12).padding(.bottom, compactHeight ? 4 : 12)
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: compactHeight ? 12 : 26) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(SaysoTheme.recording).frame(width: 8, height: 8)
                    Eyebrow(text: model.phase == .finishing ? "Finishing" : "Listening")
                        .contentTransition(reduceMotion ? .identity : .opacity)
                        .animation(reduceMotion ? nil : SaysoMotion.feedback, value: model.phase)
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
                    .monospacedDigit().font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                    .accessibilityLabel("Recording duration")
                }
            }
            Text(model.speech.partialText.isEmpty
                 ? (recording ? "I’m listening…" : "Finishing your words…")
                 : model.speech.partialText)
                .font(.system(size: writingSize, weight: .regular)).lineSpacing(8)
                .foregroundStyle(model.speech.partialText.isEmpty ? .secondary : .primary)
                // Partial recognition can replace earlier words. Keep those
                // edits immediate instead of making the reading line drift.
                .transaction { $0.animation = nil }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("liveTranscript")
            WaveformView(recording: recording, level: model.speech.level)
                .frame(height: compactHeight ? 20 : 60).padding(.top, compactHeight ? 6 : 24)
        }
        .padding(compactHeight ? 18 : 24)
        .background(SaysoTheme.paper, in: .rect(cornerRadius: 28))
        // Following new words animates the scroll position, not the internal
        // layout. A newly wrapped line and the meter must move together.
        // The status and meter retain their own explicit local animations.
        .transaction { $0.animation = nil }
    }

    private func resultContent(_ entry: Dictation) -> some View {
        let displayedText = showOriginal ? entry.original : entry.text
        let displayedWordCount = displayedText.split(whereSeparator: \.isWhitespace).count
        let actions = dynamicTypeSize >= .xLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: compactHeight ? 16 : 25) {
            if !dynamicTypeSize.isAccessibilitySize {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Label(entry.modeTitle, systemImage: entry.modeSymbol)
                        Spacer()
                        Text(entry.createdAt, format: .dateTime.month(.abbreviated).day())
                    }
                    Label(entry.modeTitle, systemImage: entry.modeSymbol)
                }
                .font(.subheadline.weight(.medium)).foregroundStyle(SaysoTheme.accent)
                Rectangle().fill(SaysoTheme.hairline).frame(height: 1).accessibilityHidden(true)
                HStack {
                    Eyebrow(text: model.phase == .refining ? "Refining your words" : "Your words, ready")
                        .contentTransition(reduceMotion ? .identity : .opacity)
                        .animation(reduceMotion ? nil : SaysoMotion.feedback, value: model.phase)
                    Spacer()
                    Text("\(displayedWordCount) words").font(.caption).foregroundStyle(SaysoTheme.secondaryInk)
                }
            }
            Text(displayedText)
                .font(.system(size: writingSize, weight: .regular)).lineSpacing(9)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("resultText")
                // Different versions can have different heights. Update the
                // words and layout together, without drawing old lines over actions.
                .transaction { $0.animation = nil }
            if let note = model.resultNote { information(note, symbol: "info.circle") }
            actions {
                Button { model.copy(showOriginal ? entry.original : entry.text) } label: {
                    ZStack {
                        Label("Copied", systemImage: "document.on.document")
                            .hidden().accessibilityHidden(true)
                        Label {
                            Text(model.copied ? "Copied" : "Copy")
                                .contentTransition(reduceMotion ? .identity : .opacity)
                        } icon: {
                            Image(systemName: model.copied ? "checkmark" : "document.on.document")
                                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        }
                    }
                    .font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    .animation(reduceMotion ? nil : SaysoMotion.feedback, value: model.copied)
                }.buttonStyle(SaysoPrimaryButtonStyle()).accessibilityIdentifier("copyButton")
                ShareLink(item: showOriginal ? entry.original : entry.text) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 18)).frame(width: 44, height: 44)
                }.buttonStyle(SaysoQuietButtonStyle()).accessibilityLabel("Share text")
                Button { editText = entry.text; sheet = .edit } label: {
                    Image(systemName: "pencil").font(.system(size: 18)).frame(width: 44, height: 44)
                }.buttonStyle(SaysoQuietButtonStyle()).accessibilityLabel("Edit text").accessibilityIdentifier("editButton")
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            }.disabled(model.isBusy)
            actions {
                if entry.original != entry.text {
                    Button { showOriginal.toggle(); model.copied = false } label: {
                        Text(showOriginal ? "Show refined" : "Show original")
                            .contentTransition(reduceMotion ? .identity : .opacity)
                            .animation(reduceMotion ? nil : SaysoMotion.feedback, value: showOriginal)
                            .frame(minHeight: 44).contentShape(.rect)
                    }
                        .buttonStyle(SaysoPressButtonStyle())
                        .accessibilityIdentifier("originalButton")
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
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
                } label: {
                    Label("Rewrite", systemImage: "sparkles")
                        .frame(minHeight: 44).contentShape(.rect)
                }
                    .accessibilityIdentifier("rewriteButton")
            }.font(.subheadline.weight(.medium)).foregroundStyle(SaysoTheme.accent).frame(minHeight: 44).disabled(model.isBusy)
            if dynamicTypeSize.isAccessibilitySize {
                // At large reading sizes, the writing and its actions take
                // priority over context that would fill the first viewport.
                VStack(alignment: .leading, spacing: 8) {
                    Label(entry.modeTitle, systemImage: entry.modeSymbol)
                        .foregroundStyle(SaysoTheme.accent)
                    Text("\(displayedWordCount) words")
                    Text(entry.createdAt, format: .dateTime.month(.abbreviated).day())
                }
                .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
            }
        }
        .padding(compactHeight ? 18 : 24)
        .background(SaysoTheme.paper, in: .rect(cornerRadius: 28))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if model.phase == .preparing || model.phase == .finishing || model.phase == .refining {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(progressMessage)
                        .font(.footnote).foregroundStyle(SaysoTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Cancel") { model.cancel() }
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                        .disabled(!model.canCancel)
                }
            }
            if !model.isBusy { modeControl }
            if recording && !dynamicTypeSize.isAccessibilitySize {
                Text("Keep Sayso open while you speak.")
                    .font(.footnote).foregroundStyle(SaysoTheme.secondaryInk)
            }
            recordControl
                .padding(.top, 4)
            if recording {
                Button("Discard recording") { discardRecording = true }
                    .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("discardRecordingButton")
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(SaysoTheme.canvas)
        .animation(reduceMotion ? nil : SaysoMotion.settle, value: model.phase)
    }

    private var compactControls: some View {
        VStack(spacing: 6) {
            // Provider configuration stays in Settings; one control row leaves
            // room to read and review a thought in landscape.
            if model.phase == .preparing || model.phase == .finishing || model.phase == .refining {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progressMessage)
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            HStack(spacing: 12) {
                if !model.isBusy { modeControl }
                else { Spacer(minLength: 0) }
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
        .animation(reduceMotion ? nil : SaysoMotion.settle, value: model.phase)
    }

    private var modeControl: some View {
        Button { sheet = .modes } label: {
            HStack(spacing: 9) {
                Image(systemName: mode.symbol).font(.system(size: 18)).foregroundStyle(SaysoTheme.accent)
                    .frame(width: 28)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 3) {
                    if !compactHeight && !dynamicTypeSize.isAccessibilitySize {
                        Text("WRITING MODE").font(.caption2.weight(.semibold)).tracking(1.2)
                            .foregroundStyle(SaysoTheme.secondaryInk)
                    }
                    Text(mode.title)
                        .font(dynamicTypeSize.isAccessibilitySize ? .headline : .subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(reduceMotion ? .identity : .opacity)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            .foregroundStyle(SaysoTheme.ink)
            .padding(.horizontal, 16).padding(.vertical, compactHeight ? 0 : 8)
            .frame(maxWidth: .infinity, minHeight: compactHeight ? 44 : 56)
            .background(SaysoTheme.accentSoft, in: .rect(cornerRadius: 20))
            .contentShape(.rect)
            .animation(reduceMotion ? nil : SaysoMotion.feedback, value: mode.id)
        }
        .buttonStyle(SaysoPressButtonStyle()).disabled(model.isBusy).accessibilityIdentifier("modeButton")
        .accessibilityLabel("Writing mode, \(mode.title)")
        .accessibilityHint("Choose a dictation mode")
    }

    private var recordingActionTitle: String {
        if dynamicTypeSize.isAccessibilitySize { return recording ? "Stop" : "Dictate" }
        return recording ? "Finish dictation" : (model.current == nil ? "Start dictation" : "New dictation")
    }

    private var recordControl: some View {
        Button {
            if recording { model.finish() } else { startRecording() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: compactHeight ? 23 : 19, weight: .medium))
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                if !compactHeight {
                    Text(recordingActionTitle)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(reduceMotion ? .identity : .opacity)
                }
            }
            .frame(maxWidth: compactHeight ? nil : .infinity, minHeight: compactHeight ? 28 : 30)
            .animation(reduceMotion ? nil : SaysoMotion.feedback, value: recording)
        }
        .buttonStyle(SaysoPrimaryButtonStyle())
        .disabled(model.isBusy && !recording)
        .accessibilityLabel(recording ? "Stop recording" : "Start recording")
        .accessibilityInputLabels([Text(recordingActionTitle), Text(recording ? "Stop recording" : "Start recording")])
        .accessibilityHint(recording ? "Finish and prepare your text" : "Turn your voice into text")
        .accessibilityIdentifier("recordButton")
    }

    private func information(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.footnote).foregroundStyle(.primary).lineSpacing(3)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(SaysoTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private func startRecording() {
        showOriginal = false
        model.start(mode: mode.mode, locale: locale, instructions: mode.prompt, vocabulary: vocabulary, saveHistory: saveHistory, writingStyle: mode)
    }
    private func consumeRoute() {
        guard scenePhase == .active, AppRoute.shared.recordRequest != nil else { return }
        AppRoute.shared.recordRequest = nil
        if !model.isBusy { sheet = nil; startRecording() }
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
                .font(.title3).foregroundStyle(SaysoTheme.ink)
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
