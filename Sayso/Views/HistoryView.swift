import SwiftUI

struct HistoryView: View {
    let store: DictationStore
    let styles: WritingStyleStore
    var onRewrite: (UUID, WritingStyle) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var deleting: Dictation?
    @ScaledMetric(relativeTo: .largeTitle) private var emptyTitleSize = 32.0

    private var filtered: [Dictation] {
        guard !search.isEmpty else { return store.entries }
        return store.entries.filter { $0.text.localizedStandardContains(search) || $0.original.localizedStandardContains(search) }
    }
    private var days: [Date] {
        Set(filtered.map { Calendar.current.startOfDay(for: $0.createdAt) }).sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView {
                        VStack(spacing: 24) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(SaysoTheme.accent)
                                .frame(width: 76, height: 76)
                                .background(SaysoTheme.surface, in: Circle())
                                .accessibilityHidden(true)
                            Text("A place for your words")
                                .font(.system(size: emptyTitleSize, weight: .regular, design: .serif))
                                .tracking(-0.7)
                                .foregroundStyle(SaysoTheme.ink)
                        }
                    } description: {
                        Text("Your dictations will appear here.\nSaved on this iPhone, ready when you need them.")
                            .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk).lineSpacing(4)
                    } actions: {
                        if let error = store.storageError {
                            Text(error).font(.footnote).foregroundStyle(SaysoTheme.secondaryInk)
                        }
                    }
                    .accessibilityIdentifier("emptyHistory")
                } else {
                    List {
                        if let error = store.storageError {
                            Text(error).font(.footnote).foregroundStyle(SaysoTheme.secondaryInk)
                                .listRowBackground(Color.clear)
                        }
                        if filtered.isEmpty {
                            ContentUnavailableView.search(text: search).listRowBackground(Color.clear)
                        }
                        ForEach(days, id: \.self) { day in
                            Section {
                                ForEach(filtered.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: day) }) { entry in
                                    NavigationLink {
                                        HistoryDetailView(entry: entry, store: store, styles: styles, onRewrite: onRewrite)
                                    } label: {
                                        historyRow(entry)
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparatorTint(SaysoTheme.hairline)
                                    .swipeActions { Button("Delete", role: .destructive) { deleting = entry } }
                                }
                            } header: {
                                Text(dayTitle(day)).font(.subheadline.weight(.medium))
                                    .foregroundStyle(SaysoTheme.secondaryInk)
                                    .textCase(nil).padding(.top, 12)
                            }
                        }
                    }
                    .accessibilityIdentifier("historyList")
                    .listStyle(.plain).scrollContentBackground(.hidden)
                    .searchable(text: $search, prompt: "Find a thought")
                }
            }
            .background(SaysoTheme.canvas)
            .tint(SaysoTheme.accent)
            .navigationTitle("History")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete this dictation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete dictation", role: .destructive) { if let deleting { store.delete(deleting.id) }; deleting = nil }
            } message: { Text("This removes both the text and its original transcript from this iPhone.") }
        }
    }

    private func historyRow(_ entry: Dictation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entry.text)
                .font(.body).foregroundStyle(SaysoTheme.ink)
                .lineLimit(3).lineSpacing(5)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(entry.modeTitle)
                    Text("·").accessibilityHidden(true)
                    Text(entry.createdAt, format: .dateTime.hour().minute())
                    Spacer(minLength: 0)
                    Text("\(entry.wordCount) words")
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.modeTitle)
                    Text(entry.createdAt, format: .dateTime.hour().minute())
                    Text("\(entry.wordCount) words")
                }
            }
            .font(.caption).foregroundStyle(SaysoTheme.secondaryInk)
        }
        .padding(.vertical, 18)
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.month(.wide).day().year())
    }
}

struct HistoryDetailView: View {
    let entry: Dictation
    let store: DictationStore
    let styles: WritingStyleStore
    var onRewrite: (UUID, WritingStyle) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var writingSize = 23.0
    @State private var showOriginal = false
    @State private var copied = false
    @State private var managingModes = false
    @State private var editing = false
    @State private var draft = ""
    private var saved: Dictation { store.entries.first { $0.id == entry.id } ?? entry }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Label(saved.modeTitle, systemImage: saved.modeSymbol)
                        Spacer()
                        Text("\(saved.wordCount) words")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label(saved.modeTitle, systemImage: saved.modeSymbol)
                        Text("\(saved.wordCount) words")
                    }
                }
                .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                rule
                Text(showOriginal ? saved.original : saved.text)
                    .font(.system(size: writingSize)).foregroundStyle(SaysoTheme.ink)
                    .lineSpacing(8).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transaction { $0.animation = nil }
                    .accessibilityIdentifier("historyDetailText")
                rule
                actionsLayout {
                    Button {
                        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: showOriginal ? saved.original : saved.text]], options: [.localOnly: true])
                        copied = true
                    } label: {
                        ZStack {
                            // Confirmation keeps its footprint, so adjacent actions stay put.
                            Label("Copied", systemImage: "document.on.document")
                                .hidden().accessibilityHidden(true)
                            Label {
                                Text(copied ? "Copied" : "Copy")
                                    .contentTransition(reduceMotion ? .identity : .opacity)
                            } icon: {
                                Image(systemName: copied ? "checkmark" : "document.on.document")
                                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                            }
                            .animation(reduceMotion ? nil : SaysoMotion.feedback, value: copied)
                        }
                    }
                    .buttonStyle(SaysoPrimaryButtonStyle())
                    HStack(spacing: 12) {
                        ShareLink(item: showOriginal ? saved.original : saved.text) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(SaysoQuietButtonStyle()).accessibilityLabel("Share text")
                        Button { draft = saved.text; editing = true } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(SaysoQuietButtonStyle()).accessibilityLabel("Edit text")
                    }
                }
                .font(.subheadline.weight(.medium))
                actionsLayout {
                    if saved.original != saved.text {
                        Button { showOriginal.toggle(); copied = false } label: {
                            Text(showOriginal ? "Show refined" : "Show original")
                                .frame(minHeight: 44, alignment: .leading).contentShape(.rect)
                                .contentTransition(reduceMotion ? .identity : .opacity)
                                .animation(reduceMotion ? nil : SaysoMotion.feedback, value: showOriginal)
                        }
                            .buttonStyle(SaysoPressButtonStyle())
                            .accessibilityIdentifier("historyOriginalButton")
                    }
                    if dynamicTypeSize < .xLarge { Spacer() }
                    Menu {
                        ForEach(styles.styles) { mode in
                            Button { onRewrite(saved.id, mode) } label: { Label(mode.title, systemImage: mode.symbol) }
                                .disabled(mode.mode != .transcript && mode.prompt.isEmpty)
                                .accessibilityIdentifier("history-rewrite-\(mode.id)")
                        }
                        Divider()
                        Button("Edit prompts & modes", systemImage: "slider.horizontal.3") { managingModes = true }
                    } label: { Label("Rewrite", systemImage: "sparkles").frame(minHeight: 44) }
                        .accessibilityIdentifier("historyRewriteButton")
                }
                .font(.subheadline.weight(.medium)).foregroundStyle(SaysoTheme.accent)
                if let error = store.storageError { Text(error).font(.footnote).foregroundStyle(SaysoTheme.secondaryInk) }
            }
            .padding(.horizontal, 26).padding(.vertical, 30)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("historyDetailScrollView")
        .background(SaysoTheme.canvas)
        .tint(SaysoTheme.accent)
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
                TextEditor(text: $draft)
                    .font(.title3).lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .padding(20).background(SaysoTheme.canvas)
                    .navigationTitle("Edit text").navigationBarTitleDisplayMode(.inline)
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

    private var rule: some View {
        Rectangle().fill(SaysoTheme.hairline).frame(height: 1).accessibilityHidden(true)
    }

    private var actionsLayout: AnyLayout {
        dynamicTypeSize >= .xLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    }
}
