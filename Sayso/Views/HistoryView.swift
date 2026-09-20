import SwiftUI

struct HistoryView: View {
    let store: DictationStore
    let styles: WritingStyleStore
    var onRewrite: (UUID, WritingStyle) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var search = ""
    @State private var deleting: Dictation?
    @ScaledMetric(relativeTo: .largeTitle) private var emptyTitleSize = 34.0

    private var filtered: [Dictation] {
        guard !search.isEmpty else { return store.entries }
        return store.entries.filter { $0.text.localizedStandardContains(search) || $0.original.localizedStandardContains(search) }
    }
    var body: some View {
        let grouped = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.createdAt) }
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    GeometryReader { geometry in
                        ScrollView {
                            VStack(spacing: 24) {
                                Image(systemName: "text.book.closed")
                                    .font(.largeTitle.weight(.light))
                                    .foregroundStyle(SaysoTheme.accent)
                                    .frame(width: 88, height: 88)
                                    .background(SaysoTheme.accentSoft, in: .rect(cornerRadius: 28))
                                    .accessibilityHidden(true)
                                Text("A place for your words.")
                                    .font(.system(size: emptyTitleSize, weight: .regular, design: .serif))
                                    .tracking(-0.7)
                                    .foregroundStyle(SaysoTheme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Speak a thought. Keep it here.\nYour saved dictations will be ready to copy, edit, or revisit.")
                                    .font(.body).foregroundStyle(SaysoTheme.secondaryInk).lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let error = store.storageError {
                                    Text(error).font(.footnote).foregroundStyle(SaysoTheme.secondaryInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Button("Back to writing") { dismiss() }
                                    .buttonStyle(SaysoPrimaryButtonStyle())
                            }
                            .multilineTextAlignment(.center)
                            .padding(24)
                            .frame(maxWidth: 560)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: geometry.size.height)
                            .accessibilityIdentifier("emptyHistory")
                        }
                        .accessibilityIdentifier("emptyHistoryScrollView")
                    }
                } else {
                    List {
                        if search.isEmpty && !dynamicTypeSize.isAccessibilitySize {
                            Section {
                                VStack(alignment: .leading, spacing: 8) {
                                    Eyebrow(text: "Your collection")
                                    Text("Words worth keeping.")
                                        .font(.system(.title2, design: .serif))
                                        .foregroundStyle(SaysoTheme.ink)
                                    Text("\(store.entries.count) saved \(store.entries.count == 1 ? "dictation" : "dictations") · stored on this iPhone")
                                        .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, 8)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                                .listRowBackground(Color.clear)
                            }
                        }
                        if let error = store.storageError {
                            Text(error).font(.footnote).foregroundStyle(SaysoTheme.secondaryInk)
                                .listRowBackground(Color.clear)
                        }
                        if grouped.isEmpty {
                            ContentUnavailableView.search(text: search).listRowBackground(Color.clear)
                        }
                        ForEach(grouped.keys.sorted(by: >), id: \.self) { day in
                            Section {
                                ForEach(grouped[day] ?? []) { entry in
                                    NavigationLink {
                                        HistoryDetailView(entry: entry, store: store, styles: styles, onRewrite: onRewrite)
                                    } label: {
                                        historyRow(entry)
                                    }
                                    .listRowBackground(SaysoTheme.paper)
                                    .listRowSeparatorTint(SaysoTheme.hairline)
                                    .swipeActions { Button("Delete", role: .destructive) { deleting = entry } }
                                    .contextMenu {
                                        Button("Delete dictation", systemImage: "trash", role: .destructive) { deleting = entry }
                                    }
                                }
                            } header: {
                                Text(dayTitle(day)).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SaysoTheme.secondaryInk)
                                    .textCase(nil)
                            }
                        }
                        if search.isEmpty && dynamicTypeSize.isAccessibilitySize {
                            Text("\(store.entries.count) saved \(store.entries.count == 1 ? "dictation" : "dictations") · stored on this iPhone")
                                .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .accessibilityIdentifier("historyList")
                    .listStyle(.insetGrouped).scrollContentBackground(.hidden)
                    .searchable(text: $search, prompt: "Search your words")
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
        VStack(alignment: .leading, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Label(entry.modeTitle, systemImage: entry.modeSymbol)
                    .font(.caption.weight(.semibold)).foregroundStyle(SaysoTheme.accent)
            }
            Text(entry.text)
                .font(.body).foregroundStyle(SaysoTheme.ink)
                .lineLimit(3).lineSpacing(4)
            if dynamicTypeSize.isAccessibilitySize {
                Label(entry.modeTitle, systemImage: entry.modeSymbol)
                    .font(.caption.weight(.semibold)).foregroundStyle(SaysoTheme.accent)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(entry.createdAt, format: .dateTime.hour().minute())
                    Text("·").accessibilityHidden(true)
                    Text("\(entry.wordCount) words")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.createdAt, format: .dateTime.hour().minute())
                    Text("\(entry.wordCount) words")
                }
            }
            .font(.caption).foregroundStyle(SaysoTheme.secondaryInk)
        }
        .padding(.vertical, 12)
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
    private var displayedText: String { showOriginal ? saved.original : saved.text }
    private var displayedWordCount: Int { displayedText.split(whereSeparator: \.isWhitespace).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !dynamicTypeSize.isAccessibilitySize { dictationMetadata }
                VStack(alignment: .leading, spacing: 20) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        HStack {
                            Eyebrow(text: showOriginal ? "Original transcript" : "Your words")
                            Spacer(minLength: 0)
                            Image(systemName: "quote.opening").font(.title2)
                                .foregroundStyle(SaysoTheme.accent).accessibilityHidden(true)
                        }
                    }
                    Text(displayedText)
                        .font(.system(size: writingSize)).foregroundStyle(SaysoTheme.ink)
                        .lineSpacing(8).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transaction { $0.animation = nil }
                        .accessibilityIdentifier("historyDetailText")
                }
                .padding(dynamicTypeSize.isAccessibilitySize ? 20 : 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SaysoTheme.paper, in: .rect(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(SaysoTheme.hairline, lineWidth: 1).accessibilityHidden(true) }
                actionsLayout {
                    Button {
                        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: displayedText]], options: [.localOnly: true])
                        copied = true
                    } label: {
                        CopyLabel(copied: copied)
                    }
                    .buttonStyle(SaysoPrimaryButtonStyle())
                    HStack(spacing: 12) {
                        ShareLink(item: displayedText) {
                            Label("Share text", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
                        }
                        .buttonStyle(SaysoQuietButtonStyle()).accessibilityLabel("Share text")
                        Button { draft = saved.text; editing = true } label: {
                            Label("Edit text", systemImage: "pencil").labelStyle(.iconOnly)
                        }
                        .buttonStyle(SaysoQuietButtonStyle()).accessibilityLabel("Edit text")
                    }
                }
                .font(.subheadline.weight(.medium))
                VStack(alignment: .leading, spacing: 8) {
                    actionsLayout {
                        Menu {
                            ForEach(styles.styles) { mode in
                                Button { onRewrite(saved.id, mode) } label: { Label(mode.title, systemImage: mode.symbol) }
                                    .disabled(mode.mode != .transcript && mode.prompt.isEmpty)
                                    .accessibilityIdentifier("history-rewrite-\(mode.id)")
                            }
                            Divider()
                            Button("Edit prompts & modes", systemImage: "slider.horizontal.3") { managingModes = true }
                        } label: {
                            Label("Rewrite", systemImage: "sparkles").frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("historyRewriteButton")
                        if dynamicTypeSize < .xLarge { Spacer() }
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
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(SaysoTheme.accent)
                    Text("Try another style. Your original transcript stays available.")
                        .font(.footnote).foregroundStyle(SaysoTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SaysoTheme.accentSoft, in: .rect(cornerRadius: 20))
                if dynamicTypeSize.isAccessibilitySize { dictationMetadata }
                if let error = store.storageError { Text(error).font(.footnote).foregroundStyle(SaysoTheme.secondaryInk) }
            }
            .padding(.horizontal, 20).padding(.vertical, 24)
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
                Form {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Make it yours.")
                                    .font(.system(.title2, design: .serif)).foregroundStyle(SaysoTheme.ink)
                                Text("Edit the saved text. Your original transcript stays as it was.")
                                    .font(.subheadline).foregroundStyle(SaysoTheme.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                    }
                    Section {
                        TextEditor(text: $draft)
                            .font(.title3).lineSpacing(6)
                            .frame(minHeight: 240)
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel("Saved dictation text")
                    } footer: {
                        if dynamicTypeSize.isAccessibilitySize {
                            Text("Edit the saved text. Your original transcript stays as it was.")
                        }
                    }
                    .listRowBackground(SaysoTheme.paper)
                    if let error = store.storageError {
                        Section { Text(error).font(.footnote).foregroundStyle(.red) }
                    }
                }
                .scrollContentBackground(.hidden).background(SaysoTheme.canvas)
                .navigationTitle("Edit text").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editing = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        var updated = saved; updated.text = draft
                        if store.save(updated) {
                            showOriginal = false
                            editing = false
                        }
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
            }
        }
    }

    private var dictationMetadata: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize { Eyebrow(text: "Saved dictation") }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    Label(saved.modeTitle, systemImage: saved.modeSymbol)
                    Spacer(minLength: 0)
                    Text("\(displayedWordCount) words")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label(saved.modeTitle, systemImage: saved.modeSymbol)
                    Text("\(displayedWordCount) words")
                }
            }
            .font(.subheadline.weight(.medium)).foregroundStyle(SaysoTheme.accent)
            Text(saved.createdAt, format: .dateTime.weekday(.wide).month(.wide).day().hour().minute())
                .font(.footnote).foregroundStyle(SaysoTheme.secondaryInk)
        }
    }

    private var actionsLayout: AnyLayout {
        dynamicTypeSize >= .xLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    }
}
