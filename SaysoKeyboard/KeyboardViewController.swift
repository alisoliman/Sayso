import UIKit

/// A dictation control panel. Audio stays in Sayso; completed words are inserted
/// through the current document proxy without reading its surrounding text.
@MainActor
final class KeyboardViewController: UIInputViewController {
    private let handoff = KeyboardHandoff()
    private let recordingSessions = KeyboardRecordingSessionStore()
    private let stack = UIStackView()
    private let preview = UILabel()
    private let instruction = UILabel()
    private let modeScroll = UIScrollView()
    private let modeStack = UIStackView()
    private let actions = UIStackView()
    private let insertButton = UIButton(type: .system)
    private let discardButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let footer = UIStackView()
    private var heightConstraint: NSLayoutConstraint?
    private var modeHeightConstraint: NSLayoutConstraint?
    private var visibleSession: KeyboardRecordingSessionStore.Session?
    private var visiblePayload: KeyboardHandoff.Payload?
    private var availableModes: [KeyboardRecordingSessionStore.Mode] = []
    private var selectedModeID: String?
    private var refreshTimer: Timer?
    private var pendingInsertion: PendingInsertion?
    private var submittedControl: (sessionID: UUID, action: KeyboardRecordingSessionStore.Action)?
    private var isVisible = false
    private var isRefreshing = false
    private var lastCompactHeight: Bool?
    private var lastContentSize: UIContentSizeCategory?
    private let consumedKey = "lastInsertedHandoff"
    private var renderedHandoffState: HandoffVisualState?
    private var handoffIsVisible = false
    private let handoffRevealKey = "sayso.handoffReveal"

    private enum HandoffVisualState: Equatable {
        case empty, unavailable
        case session(UUID, KeyboardRecordingSessionStore.Phase)
        case result(String, consumed: Bool)
    }

    private struct PendingInsertion {
        let sessionID: UUID
        let documentID: UUID
        let requestedAt: Date
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KeyboardPalette.canvas
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
        let height = view.heightAnchor.constraint(equalToConstant: preferredKeyboardHeight)
        height.priority = .defaultHigh
        height.isActive = true
        heightConstraint = height
        configurePanel()
        for name in [Notification.Name.NSExtensionHostWillResignActive,
                     Notification.Name.NSExtensionHostDidEnterBackground] {
            NotificationCenter.default.addObserver(self, selector: #selector(revokeAutomaticInsertionForHostInactivity(_:)),
                                                   name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reduceMotionSettingChanged),
                                               name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitVerticalSizeClass.self]) { (controller: KeyboardViewController, _) in
            controller.updateKeyboardLayout()
        }
        updateKeyboardLayout()
        refreshHandoff()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        refreshHandoff()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHandoff() }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handoffIsVisible = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        handoffIsVisible = false
        renderedHandoffState = nil
        stopHandoffMotion()
        // Leaving this visible field ends the automatic-insertion gesture.
        // A completed result remains available through explicit Insert.
        pendingInsertion = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc private func revokeAutomaticInsertionForHostInactivity(_ notification: Notification) {
        // A host can retain this view while switching apps. Losing host focus
        // ends the insertion gesture even before viewWillDisappear arrives.
        // Keep the submitted command so returning cannot send Stop twice.
        pendingInsertion = nil
        stopHandoffMotion()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateKeyboardLayout()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        invalidateInsertionForChangedDocument()
        refreshHandoff()
    }

    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput)
        invalidateInsertionForChangedDocument()
    }

    private func configurePanel() {
        preview.font = UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: .systemFont(ofSize: 18, weight: .semibold), maximumPointSize: 28)
        preview.adjustsFontForContentSizeCategory = true
        preview.textColor = KeyboardPalette.ink
        preview.numberOfLines = 2
        preview.lineBreakMode = .byTruncatingTail
        preview.accessibilityIdentifier = "keyboardPreview"
        stack.addArrangedSubview(preview)

        modeScroll.showsHorizontalScrollIndicator = false
        modeScroll.alwaysBounceHorizontal = false
        modeScroll.accessibilityIdentifier = "keyboardRecordingModes"
        modeStack.axis = .horizontal
        modeStack.spacing = 8
        modeStack.translatesAutoresizingMaskIntoConstraints = false
        modeScroll.addSubview(modeStack)
        NSLayoutConstraint.activate([
            modeStack.leadingAnchor.constraint(equalTo: modeScroll.contentLayoutGuide.leadingAnchor),
            modeStack.trailingAnchor.constraint(equalTo: modeScroll.contentLayoutGuide.trailingAnchor),
            modeStack.topAnchor.constraint(equalTo: modeScroll.contentLayoutGuide.topAnchor),
            modeStack.bottomAnchor.constraint(equalTo: modeScroll.contentLayoutGuide.bottomAnchor),
            modeStack.heightAnchor.constraint(equalTo: modeScroll.frameLayoutGuide.heightAnchor)
        ])
        let modeHeight = modeScroll.heightAnchor.constraint(equalToConstant: 58)
        modeHeight.isActive = true
        modeHeightConstraint = modeHeight
        stack.addArrangedSubview(modeScroll)

        actions.axis = .horizontal
        actions.spacing = 10
        actions.alignment = .fill
        var primary = UIButton.Configuration.filled()
        primary.cornerStyle = .large
        primary.imagePadding = 8
        primary.baseBackgroundColor = KeyboardPalette.accent
        primary.baseForegroundColor = KeyboardPalette.onAccent
        primary.contentInsets = .init(top: 13, leading: 16, bottom: 13, trailing: 16)
        insertButton.configuration = primary
        insertButton.accessibilityIdentifier = "keyboardInsertButton"
        insertButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        insertButton.addTarget(self, action: #selector(performPrimaryAction), for: .touchUpInside)
        actions.addArrangedSubview(insertButton)

        var discard = UIButton.Configuration.tinted()
        discard.image = UIImage(systemName: "xmark")
        discard.cornerStyle = .large
        discard.baseForegroundColor = KeyboardPalette.secondaryInk
        discard.contentInsets = .init(top: 13, leading: 16, bottom: 13, trailing: 16)
        discardButton.configuration = discard
        discardButton.accessibilityLabel = "Discard recording"
        discardButton.accessibilityIdentifier = "keyboardDiscardButton"
        discardButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
        discardButton.addTarget(self, action: #selector(discardRecording), for: .touchUpInside)
        actions.addArrangedSubview(discardButton)
        stack.addArrangedSubview(actions)

        instruction.font = UIFontMetrics(forTextStyle: .caption1)
            .scaledFont(for: .systemFont(ofSize: 13), maximumPointSize: 21)
        instruction.adjustsFontForContentSizeCategory = true
        instruction.textColor = KeyboardPalette.secondaryInk
        instruction.numberOfLines = 3
        instruction.accessibilityIdentifier = "keyboardInstruction"
        footer.axis = .horizontal
        footer.alignment = .center
        footer.spacing = 10
        var next = UIButton.Configuration.plain()
        next.title = "Keyboard"
        next.image = UIImage(systemName: "globe")
        next.imagePadding = 6
        next.baseForegroundColor = KeyboardPalette.ink
        next.contentInsets = .init(top: 10, leading: 0, bottom: 10, trailing: 6)
        nextButton.configuration = next
        nextButton.accessibilityIdentifier = "keyboardNextButton"
        nextButton.accessibilityLabel = "Next keyboard"
        nextButton.accessibilityHint = "Tap to switch keyboards. Hold to choose the Apple keyboard."
        nextButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        nextButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        nextButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        // Keep this convenience switch visible even when iOS also supplies a
        // globe below the extension. UIKit owns the available keyboard list.
        nextButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        footer.addArrangedSubview(nextButton)
        footer.addArrangedSubview(instruction)
        stack.addArrangedSubview(footer)
    }

    private func updateKeyboardLayout() {
        let compact = usesCompactHeight
        let contentSize = traitCollection.preferredContentSizeCategory
        guard lastCompactHeight != compact || lastContentSize != contentSize else { return }
        lastCompactHeight = compact
        lastContentSize = contentSize
        let accessibility = contentSize.isAccessibilityCategory
        heightConstraint?.constant = preferredKeyboardHeight
        stack.spacing = compact ? 6 : 12
        modeHeightConstraint?.constant = compact ? 48 : accessibility ? 74 : 58
        preview.numberOfLines = compact ? 1 : 2
        instruction.numberOfLines = compact ? 2 : 3
        let font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 17, weight: .semibold), maximumPointSize: compact ? 23 : 28,
            compatibleWith: traitCollection)
        // Button symbols otherwise follow UIKit's uncapped Dynamic Type size,
        // even when the title font is bounded. Keep images within their rows.
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: font.pointSize, weight: .semibold)
        if var configuration = insertButton.configuration {
            configuration.contentInsets = .init(top: 10, leading: 16, bottom: 10, trailing: 16)
            configuration.preferredSymbolConfigurationForImage = symbolConfiguration
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes
                result.font = font
                return result
            }
            insertButton.configuration = configuration
        }
        if var configuration = discardButton.configuration {
            configuration.preferredSymbolConfigurationForImage = symbolConfiguration
            configuration.contentInsets = .init(top: 10, leading: 10, bottom: 10, trailing: 10)
            discardButton.configuration = configuration
        }
        if var configuration = nextButton.configuration {
            configuration.title = compact && accessibility ? nil : "Keyboard"
            configuration.preferredSymbolConfigurationForImage = symbolConfiguration
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes
                result.font = font
                return result
            }
            nextButton.configuration = configuration
        }
        updateModeButtons()
    }

    private func refreshHandoff() {
        guard !isRefreshing else { return }
        isRefreshing = true
        var nextState = HandoffVisualState.unavailable
        defer {
            revealHandoffChange(to: nextState)
            isRefreshing = false
        }
        preview.font = UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: .systemFont(ofSize: 18, weight: .semibold), maximumPointSize: 28,
                        compatibleWith: traitCollection)
        invalidateInsertionForChangedDocument()
        let previousSessionID = visibleSession?.id
        do {
            let session = try recordingSessions.latest()
            visibleSession = session
            if let session {
                nextState = .session(session.id, session.phase)
                preview.font = UIFontMetrics(forTextStyle: .headline)
                    .scaledFont(for: .monospacedDigitSystemFont(ofSize: 18, weight: .semibold), maximumPointSize: 28,
                                compatibleWith: traitCollection)
                visiblePayload = nil
                if previousSessionID != session.id {
                    selectedModeID = session.selectedModeID
                }
                updateModes(session.availableModes ?? [], selectedID: selectedModeID)
                if submittedControl?.sessionID != session.id { submittedControl = nil }
                let recording = session.phase == .recording
                let stopping = submittedControl?.action == .stop
                let discarding = submittedControl?.action == .cancel
                let waitingForControl = submittedControl != nil
                modeScroll.isHidden = availableModes.isEmpty
                for button in modeStack.arrangedSubviews { (button as? UIButton)?.isEnabled = hasFullAccess && recording && !waitingForControl }
                let elapsed = Int(max(0, min(Date().timeIntervalSince(session.startedAt), KeyboardRecordingSessionStore.recordingLimit)))
                switch session.phase {
                case .recording: preview.text = stopping ? "Finishing your words…" : String(format: "Recording · %d:%02d", elapsed / 60, elapsed % 60)
                case .finishing: preview.text = "Finishing your words…"
                case .refining: preview.text = "Polishing your words…"
                }
                if discarding { preview.text = "Discarding recording…" }
                setPrimary(title: recording && !waitingForControl ? "Stop & insert" : discarding ? "Discarding…" : "Finishing…",
                           symbol: recording && !waitingForControl ? "stop.fill" : "ellipsis",
                           enabled: hasFullAccess && recording && !waitingForControl)
                insertButton.accessibilityHint = "Stops recording and inserts the result in this text field."
                discardButton.isHidden = !hasFullAccess
                discardButton.isEnabled = !discarding
                instruction.text = hasFullAccess ? (discarding ? "Your recording will be discarded." : stopping ? "Your text will appear here." : "Choose a style, then stop.")
                    : "Stop in Sayso. Full Access enables these controls."
                return
            }
            submittedControl = nil
            modeScroll.isHidden = true
            discardButton.isHidden = true
            guard let payload = try handoff.latest() else {
                nextState = .empty
                visiblePayload = nil
                preview.text = "Ready for your voice"
                instruction.text = "Start dictation in Sayso, then return here."
                actions.isHidden = true
                return
            }
            visiblePayload = payload
            if canAutomaticallyInsert(payload) { insert(payload) }
            let consumed = isConsumed(payload)
            nextState = .result(payload.consumptionIdentifier, consumed: consumed)
            preview.text = payload.text
            instruction.text = consumed ? "Inserted." : "Ready at your cursor."
            setPrimary(title: consumed ? "Inserted" : "Insert", symbol: consumed ? "checkmark" : "arrow.up.doc", enabled: !consumed)
            insertButton.accessibilityHint = "Inserts this result at your current cursor."
        } catch {
            visibleSession = nil
            visiblePayload = nil
            pendingInsertion = nil
            modeScroll.isHidden = true
            actions.isHidden = true
            preview.text = "Open Sayso to dictate"
            instruction.text = "Return here when your words are ready."
        }
    }

    private func revealHandoffChange(to state: HandoffVisualState) {
        let previous = renderedHandoffState
        renderedHandoffState = state
        guard let previous, previous != state else { return }
        revealHandoffContent([preview, instruction, insertButton])
    }

    private func revealHandoffContent(_ views: [UIView]) {
        guard handoffIsVisible, !UIAccessibility.isReduceMotionEnabled else { return }
        // Content and enabled states have already changed. Reveal the new
        // information without retaining an old recording snapshot, moving controls,
        // or waiting for an animation before an insertion/control action runs.
        for target in views {
            let reveal = CABasicAnimation(keyPath: "opacity")
            reveal.fromValue = target.layer.animation(forKey: handoffRevealKey) == nil
                ? 0.65 : (target.layer.presentation()?.opacity ?? 0.65)
            reveal.toValue = 1
            reveal.duration = 0.18
            reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
            target.layer.add(reveal, forKey: handoffRevealKey)
        }
    }

    @objc private func reduceMotionSettingChanged() {
        if UIAccessibility.isReduceMotionEnabled { stopHandoffMotion() }
    }

    private func stopHandoffMotion() {
        for target in [preview, instruction, insertButton] as [UIView] {
            target.layer.removeAnimation(forKey: handoffRevealKey)
        }
    }

    private func updateModes(_ modes: [KeyboardRecordingSessionStore.Mode], selectedID: String?) {
        if !modes.contains(where: { $0.id == self.selectedModeID }) {
            self.selectedModeID = modes.first(where: { $0.id == selectedID })?.id ?? modes.first?.id
        }
        guard availableModes != modes else { updateModeButtons(); return }
        availableModes = modes
        for child in modeStack.arrangedSubviews {
            modeStack.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        for mode in modes {
            let button = UIButton(type: .system)
            button.accessibilityIdentifier = "keyboardMode-\(mode.id)"
            button.accessibilityLabel = mode.title
            button.accessibilityHint = "Use this style for the recording."
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 86).isActive = true
            button.addAction(UIAction { [weak self] _ in
                self?.selectedModeID = mode.id
                self?.updateModeButtons()
            }, for: .touchUpInside)
            modeStack.addArrangedSubview(button)
            // Cross-view constraints require a common ancestor before activation.
            button.widthAnchor.constraint(lessThanOrEqualTo: modeScroll.frameLayoutGuide.widthAnchor, multiplier: 0.9).isActive = true
        }
        updateModeButtons()
    }

    private func updateModeButtons() {
        for (mode, view) in zip(availableModes, modeStack.arrangedSubviews) {
            guard let button = view as? UIButton else { continue }
            let selected = mode.id == selectedModeID
            var configuration = UIButton.Configuration.tinted()
            configuration.title = mode.title
            configuration.titleLineBreakMode = .byTruncatingTail
            configuration.image = UIImage(systemName: mode.symbol)
            configuration.imagePadding = 6
            configuration.cornerStyle = .medium
            configuration.baseForegroundColor = selected ? KeyboardPalette.ink : KeyboardPalette.secondaryInk
            configuration.baseBackgroundColor = selected ? KeyboardPalette.accent : KeyboardPalette.utilityKey
            configuration.contentInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 12)
            let font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
                for: .systemFont(ofSize: 15, weight: selected ? .semibold : .regular), maximumPointSize: 23,
                compatibleWith: traitCollection)
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
                pointSize: font.pointSize, weight: selected ? .semibold : .regular)
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes
                result.font = font
                return result
            }
            button.configuration = configuration
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
    }

    private func setPrimary(title: String, symbol: String, enabled: Bool) {
        actions.isHidden = false
        insertButton.configuration?.title = title
        insertButton.configuration?.image = UIImage(systemName: symbol)
        insertButton.isEnabled = enabled
    }

    @objc private func performPrimaryAction() {
        if let session = visibleSession {
            guard hasFullAccess, session.phase == .recording else { return }
            do {
                let requestedAt = Date()
                let documentID = currentDocumentID
                try recordingSessions.send(.stop, sessionID: session.id, modeID: selectedModeID, now: requestedAt)
                submittedControl = (session.id, .stop)
                pendingInsertion = documentID.map {
                    PendingInsertion(sessionID: session.id, documentID: $0, requestedAt: requestedAt)
                }
                refreshHandoff()
                revealHandoffContent([preview, instruction, insertButton])
            } catch {
                refreshHandoff()
                instruction.text = error.localizedDescription
            }
            return
        }
        guard let shown = visiblePayload else { return }
        do {
            guard let latest = try handoff.latest(), latest == shown, !isConsumed(latest) else {
                refreshHandoff()
                return
            }
            pendingInsertion = nil
            insert(latest)
            refreshHandoff()
        } catch { refreshHandoff() }
    }

    @objc private func discardRecording() {
        guard hasFullAccess, let session = visibleSession else { return }
        pendingInsertion = nil
        do {
            try recordingSessions.send(.cancel, sessionID: session.id)
            submittedControl = (session.id, .cancel)
            refreshHandoff()
            revealHandoffContent([preview, instruction, insertButton])
        } catch {
            refreshHandoff()
            instruction.text = error.localizedDescription
        }
    }

    private var currentDocumentID: UUID? {
        // UIKit can temporarily return nil during a field transition despite
        // this public property being declared nonnull. Calling the documented
        // Objective-C getter avoids Swift's unconditional NSUUID bridge trap.
        let getter = #selector(getter: UITextDocumentProxy.documentIdentifier)
        guard let proxy = textDocumentProxy as? NSObject,
              let identifier = proxy.perform(getter)?.takeUnretainedValue() as? NSUUID else { return nil }
        return identifier as UUID
    }

    private func invalidateInsertionForChangedDocument() {
        guard let pending = pendingInsertion else { return }
        if pending.documentID != currentDocumentID ||
            Date().timeIntervalSince(pending.requestedAt) > KeyboardRecordingSessionStore.completionAllowance + 15 {
            pendingInsertion = nil
        }
    }

    private func canAutomaticallyInsert(_ payload: KeyboardHandoff.Payload) -> Bool {
        guard isVisible, let pending = pendingInsertion else { return false }
        return payload.recordingSessionID == pending.sessionID && payload.id == pending.sessionID &&
            pending.documentID == currentDocumentID &&
            payload.createdAt >= pending.requestedAt && !isConsumed(payload)
    }

    private func isConsumed(_ payload: KeyboardHandoff.Payload) -> Bool {
        UserDefaults.standard.string(forKey: consumedKey) == payload.consumptionIdentifier
    }

    private func insert(_ payload: KeyboardHandoff.Payload) {
        // Claim before calling UIKit: insertText may synchronously notify the
        // delegate. No callback, refresh, or reopening may replay this result.
        pendingInsertion = nil
        UserDefaults.standard.set(payload.consumptionIdentifier, forKey: consumedKey)
        textDocumentProxy.insertText(payload.text)
        UIAccessibility.post(notification: .announcement, argument: "Text inserted")
    }

    private var preferredKeyboardHeight: CGFloat {
        let accessibility = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        if usesCompactHeight { return accessibility ? 228 : 204 }
        return accessibility ? 340 : 270
    }

    private var usesCompactHeight: Bool {
        traitCollection.verticalSizeClass == .compact ||
            view.window?.windowScene?.effectiveGeometry.interfaceOrientation.isLandscape == true
    }
}

// The keyboard is a separate process, so keep these appearance tokens aligned
// with SaysoTheme and ActivityPalette without importing app-only views.
private enum KeyboardPalette {
    static let canvas = dynamic(light: 0xF8F6F2, dark: 0x141218)
    static let ink = dynamic(light: 0x261F2F, dark: 0xF5F0FA)
    static let secondaryInk = dynamic(light: 0x6D6674, dark: 0xB8AEBD)
    static let accent = dynamic(light: 0x503968, dark: 0xCEB8F2)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x261F2F)
    static let utilityKey = dynamic(light: 0xE6E1E8, dark: 0x25212B)

    private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 0xFF) / 255,
                           green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
    }
}
