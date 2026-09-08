import SwiftUI

struct HistoryView: View {
    let store: DictationStore
    let styles: WritingStyleStore
    var onRewrite: (UUID, WritingStyle) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var deleting: Dictation?
    @State private var sharingError: String?
    private var filtered: [Dictation] {
        guard !search.isEmpty else { return store.entries }
        return store.entries.filter { $0.text.localizedStandardContains(search) || $0.original.localizedStandardContains(search) }
    }
    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView {
                        Label("A place for your words", systemImage: "clock")
                    } description: {
                        Text("Your dictations will appear here.\nSaved on this iPhone, ready when you need them.")
                    }.accessibilityIdentifier("emptyHistory")
                } else {
                    List {
                        if let error = store.storageError { Text(error).font(.footnote).foregroundStyle(.secondary) }
                        if filtered.isEmpty { ContentUnavailableView.search(text: search).listRowBackground(Color.clear) }
                        ForEach(filtered) { entry in
                            NavigationLink {
                                HistoryDetailView(entry: entry, store: store, styles: styles, onRewrite: onRewrite)
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(entry.text).font(.system(size: 18, design: .serif)).lineLimit(3).lineSpacing(4)
                                    HStack(spacing: 7) {
                                        Text(entry.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                        Text("·")
                                        Text(entry.modeTitle)
                                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                                }.padding(.vertical, 12)
                            }
                            .listRowBackground(Color.clear)
                            .swipeActions { Button("Delete", role: .destructive) { deleting = entry } }
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                        .searchable(text: $search, prompt: "Find a thought")
                }
            }
            .background(SaysoTheme.canvas)
            .navigationTitle("History")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete this dictation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete dictation", role: .destructive) { if let deleting { delete(deleting) }; deleting = nil }
            } message: { Text("This removes both the text and its original transcript from this iPhone.") }
            .alert("Keyboard sharing", isPresented: Binding(get: { sharingError != nil }, set: { if !$0 { sharingError = nil } })) {
                Button("OK") { sharingError = nil }
            } message: { Text(sharingError ?? "") }
        }
    }

    private func delete(_ entry: Dictation) {
        guard store.delete(entry.id) else { return }
        do {
            let handoff = KeyboardHandoff()
            try handoff.purgeExpired()
            if try handoff.latest()?.id == entry.id { try handoff.clear() }
        } catch KeyboardHandoff.HandoffError.unavailable {
            // This installation could not have shared a result with the keyboard.
        } catch {
            sharingError = "The dictation was deleted from History, but its shared keyboard copy couldn’t be cleared. " + error.localizedDescription
        }
    }
}

struct HistoryDetailView: View {
    let entry: Dictation
    let store: DictationStore
    let styles: WritingStyleStore
    var onRewrite: (UUID, WritingStyle) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var writingSize = 26.0
    @State private var showOriginal = false
    @State private var copied = false
    @State private var managingModes = false
    @State private var editing = false
    @State private var draft = ""
    private var saved: Dictation { store.entries.first { $0.id == entry.id } ?? entry }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Eyebrow(text: saved.modeTitle)
                    Spacer()
                    Text("\(saved.wordCount) words").font(.caption).foregroundStyle(.secondary)
                }
                Text(showOriginal ? saved.original : saved.text)
                    .font(.system(size: writingSize, design: .serif)).lineSpacing(9).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                actionsLayout {
                    Button {
                        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: showOriginal ? saved.original : saved.text]], options: [.localOnly: true])
                        copied = true
                    } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "document.on.document").foregroundStyle(SaysoTheme.onAccent).fixedSize().padding(.horizontal, 4).padding(.vertical, 8) }
                        .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
                    ShareLink(item: showOriginal ? saved.original : saved.text) { Image(systemName: "square.and.arrow.up").frame(width: 42, height: 42) }
                        .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Share text")
                    Button { draft = saved.text; editing = true } label: { Image(systemName: "pencil").frame(width: 42, height: 42) }
                        .buttonStyle(.glass).buttonBorderShape(.circle).accessibilityLabel("Edit text")
                    KeyboardSendButton(text: showOriginal ? saved.original : saved.text, id: saved.id)
                }.font(.system(size: 14, weight: .medium))
                HStack {
                    if saved.original != saved.text {
                        Button(showOriginal ? "Show refined" : "Show original") { showOriginal.toggle(); copied = false }
                    }
                    Spacer()
                    Menu {
                        ForEach(styles.styles) { mode in
                            Button { onRewrite(saved.id, mode) } label: { Label(mode.title, systemImage: mode.symbol) }
                                .disabled(mode.mode != .transcript && mode.prompt.isEmpty)
                                .accessibilityIdentifier("history-rewrite-\(mode.id)")
                        }
                        Divider()
                        Button("Edit prompts & modes", systemImage: "slider.horizontal.3") { managingModes = true }
                    } label: { Label("Rewrite", systemImage: "sparkles") }
                        .accessibilityIdentifier("historyRewriteButton")
                }.font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                if let error = store.storageError { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }.padding(26)
        }
        .background(SaysoTheme.canvas)
        .navigationTitle(saved.createdAt.formatted(.dateTime.month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: saved.text) { _, _ in copied = false }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copied = false
        }
        .sheet(isPresented: $managingModes) {
            NavigationStack {
                WritingModesSettingsView(styles: styles)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { managingModes = false } } }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                TextEditor(text: $draft).font(.system(size: 21)).padding(20).navigationTitle("Edit text").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Save") {
                            var updated = saved; updated.text = draft
                            if store.save(updated) { editing = false }
                        }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                    }
            }
        }
    }

    private var actionsLayout: AnyLayout {
        dynamicTypeSize >= .xLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    }
}
