import UIKit

/// Explicit dictation controls and insertion alongside a fully local keyboard.
@MainActor
final class KeyboardViewController: UIInputViewController {
    private let handoff = KeyboardHandoff()
    private let recordingSessions = KeyboardRecordingSessionStore()
    private var visibleSession: KeyboardRecordingSessionStore.Session?
    private let discardButton = UIButton(type: .system)
    private let handoffHeader = UIStackView()
    private let handoffText = UIStackView()
    private let brand = UILabel()
    private let handoffActions = UIStackView()
    private let actionSpacer = UIView()
    private let stack = UIStackView()
    private let keys = UIStackView()
    private let preview = UILabel()
    private let instruction = UILabel()
    private let insertButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private var visiblePayload: KeyboardHandoff.Payload?
    private var isShifted = false
    private var usesNumbers = false
    private var usesSymbols = false
    private var refreshTimer: Timer?
    private var deleteTimer: Timer?
    private var heightConstraint: NSLayoutConstraint?
    private var stackTopConstraint: NSLayoutConstraint?
    private var headerHeightConstraint: NSLayoutConstraint?
    private var keyRowHeightConstraints: [NSLayoutConstraint] = []
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = KeyboardPalette.canvas
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let top = stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10)
        stackTopConstraint = top
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 5),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -5),
            top,
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6)
        ])
        let height = view.heightAnchor.constraint(equalToConstant: preferredKeyboardHeight)
        height.priority = .defaultHigh
        height.isActive = true
        heightConstraint = height
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitVerticalSizeClass.self]) { (controller: KeyboardViewController, _) in
            controller.updateKeyboardLayout()
        }
        configureHandoff()
        keys.axis = .vertical
        keys.spacing = 6
        stack.addArrangedSubview(keys)
        makeKeys()
        updateKeyboardLayout()
        refreshHandoff()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(reduceMotionSettingChanged),
                                               name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        refreshHandoff()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHandoff() }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handoffIsVisible = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        handoffIsVisible = false
        renderedHandoffState = nil
        stopHandoffMotion()
        NotificationCenter.default.removeObserver(self, name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        refreshTimer?.invalidate()
        refreshTimer = nil
        stopRepeatedDeletion()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        nextButton.isHidden = !needsInputModeSwitchKey
        updateKeyboardLayout()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateKeyboardLayout()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        refreshHandoff()
    }

    private func configureHandoff() {
        let header = handoffHeader
        header.spacing = 10
        header.alignment = .center
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = .init(top: 0, leading: 7, bottom: 0, trailing: 7)

        let text = handoffText
        text.axis = .vertical
        text.spacing = 3
        let title = brand
        title.text = "SAYSO"
        title.font = UIFontMetrics(forTextStyle: .caption2)
            .scaledFont(for: .systemFont(ofSize: 10, weight: .semibold), maximumPointSize: 14)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = KeyboardPalette.secondaryInk
        title.accessibilityTraits = .header
        text.addArrangedSubview(title)
        preview.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 15), maximumPointSize: 24)
        preview.adjustsFontForContentSizeCategory = true
        preview.textColor = KeyboardPalette.ink
        preview.numberOfLines = 2
        preview.lineBreakMode = .byTruncatingTail
        preview.accessibilityIdentifier = "keyboardPreview"
        text.addArrangedSubview(preview)
        header.addArrangedSubview(text)
        handoffActions.axis = .horizontal
        handoffActions.alignment = .center
        handoffActions.spacing = 10
        handoffActions.setContentHuggingPriority(.required, for: .horizontal)
        handoffActions.setContentCompressionResistancePriority(.required, for: .horizontal)
        handoffActions.addArrangedSubview(actionSpacer)
        header.addArrangedSubview(handoffActions)

        var configuration = UIButton.Configuration.filled()
        configuration.title = "Insert"
        configuration.image = UIImage(systemName: "arrow.up.doc")
        configuration.imagePadding = 5
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = KeyboardPalette.accent
        configuration.baseForegroundColor = KeyboardPalette.onAccent
        configuration.contentInsets = .init(top: 12, leading: 13, bottom: 12, trailing: 13)
        insertButton.configuration = configuration
        insertButton.accessibilityIdentifier = "keyboardInsertButton"
        insertButton.accessibilityHint = "Inserts the shared result at the current cursor."
        insertButton.setContentHuggingPriority(.required, for: .horizontal)
        insertButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        insertButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        insertButton.addTarget(self, action: #selector(insertSharedText), for: .touchUpInside)
        handoffActions.addArrangedSubview(insertButton)
        var discard = UIButton.Configuration.plain()
        discard.image = UIImage(systemName: "xmark")
        discard.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        discard.baseForegroundColor = KeyboardPalette.secondaryInk
        discard.contentInsets = .init(top: 14, leading: 16, bottom: 14, trailing: 16)
        discardButton.configuration = discard
        discardButton.setContentHuggingPriority(.required, for: .horizontal)
        discardButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        discardButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        discardButton.accessibilityLabel = "Discard recording"
        discardButton.accessibilityIdentifier = "keyboardDiscardButton"
        discardButton.addTarget(self, action: #selector(discardRecording), for: .touchUpInside)
        discardButton.isHidden = true
        handoffActions.addArrangedSubview(discardButton)
        let minimumHeight = header.heightAnchor.constraint(greaterThanOrEqualToConstant: 66)
        minimumHeight.isActive = true
        headerHeightConstraint = minimumHeight
        stack.addArrangedSubview(header)

        instruction.font = UIFontMetrics(forTextStyle: .caption2)
            .scaledFont(for: .systemFont(ofSize: 11), maximumPointSize: 17)
        instruction.adjustsFontForContentSizeCategory = true
        instruction.textColor = KeyboardPalette.secondaryInk
        instruction.numberOfLines = 2
        instruction.textAlignment = .center
        instruction.accessibilityIdentifier = "keyboardInstruction"
        stack.addArrangedSubview(instruction)
    }

    private func updateKeyboardLayout() {
        guard headerHeightConstraint != nil else { return }
        let compact = usesCompactHeight
        let contentSize = traitCollection.preferredContentSizeCategory
        guard lastCompactHeight != compact || lastContentSize != contentSize else { return }
        lastCompactHeight = compact
        lastContentSize = contentSize
        let accessibility = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        heightConstraint?.constant = preferredKeyboardHeight
        stackTopConstraint?.constant = compact ? 6 : 10
        stack.spacing = compact ? 6 : 10
        keys.spacing = compact ? 4 : 6
        for constraint in keyRowHeightConstraints {
            constraint.constant = compact ? 36 : 42
        }
        headerHeightConstraint?.constant = compact ? 44 : 66

        // Keep the full-width AX arrangement in portrait. In landscape, use
        // the available width to retain status and actions beside the preview.
        handoffHeader.axis = accessibility && !compact ? .vertical : .horizontal
        handoffHeader.alignment = accessibility && !compact ? .fill : .center
        actionSpacer.isHidden = compact || !accessibility
        brand.isHidden = compact
        preview.numberOfLines = compact ? 1 : 2
        instruction.numberOfLines = compact ? 1 : 2
        instruction.textAlignment = compact ? .natural : .center
        if compact, instruction.superview !== handoffText {
            stack.removeArrangedSubview(instruction)
            instruction.removeFromSuperview()
            handoffText.addArrangedSubview(instruction)
        } else if !compact, instruction.superview !== stack {
            handoffText.removeArrangedSubview(instruction)
            instruction.removeFromSuperview()
            stack.insertArrangedSubview(instruction, at: 1)
        }

        if var configuration = insertButton.configuration {
            configuration.contentInsets = .init(top: compact ? 6 : 12, leading: 13,
                                                bottom: compact ? 6 : 12, trailing: 13)
            configuration.preferredSymbolConfigurationForImage = compact
                ? UIImage.SymbolConfiguration(pointSize: 20, weight: .regular) : nil
            if compact {
                // Grow the action at AX sizes without letting one button take
                // the host editor's entire height. The full label stays in VO.
                let font = UIFontMetrics(forTextStyle: .body).scaledFont(
                    for: .systemFont(ofSize: 17, weight: .semibold), maximumPointSize: 28,
                    compatibleWith: traitCollection)
                configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var result = attributes
                    result.font = font
                    return result
                }
            } else {
                configuration.titleTextAttributesTransformer = nil
            }
            insertButton.configuration = configuration
        }
        if var configuration = discardButton.configuration {
            configuration.contentInsets = .init(top: compact ? 12 : 14, leading: 16,
                                                bottom: compact ? 12 : 14, trailing: 16)
            discardButton.configuration = configuration
        }
    }

    private func refreshHandoff() {
        var nextState = HandoffVisualState.unavailable
        defer { revealHandoffChange(to: nextState) }
        visibleSession = nil
        discardButton.isHidden = true
        preview.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 15), maximumPointSize: 24)
        insertButton.configuration?.image = UIImage(systemName: "arrow.up.doc")
        insertButton.accessibilityHint = "Inserts the shared result at the current cursor."
        do {
            if let session = try recordingSessions.latest() {
                nextState = .session(session.id, session.phase)
                visibleSession = session
                visiblePayload = nil
                preview.font = UIFontMetrics(forTextStyle: .subheadline)
                    .scaledFont(for: .monospacedDigitSystemFont(ofSize: 15, weight: .medium), maximumPointSize: 24)
                let elapsed = Int(max(0, min(Date().timeIntervalSince(session.startedAt), KeyboardRecordingSessionStore.recordingLimit)))
                switch session.phase {
                case .recording: preview.text = String(format: "Recording · %d:%02d", elapsed / 60, elapsed % 60)
                case .finishing: preview.text = "Finishing your words…"
                case .refining: preview.text = "A little polish…"
                }
                insertButton.configuration?.title = session.phase == .recording ? "Stop" : "Wait"
                insertButton.configuration?.image = UIImage(systemName: session.phase == .recording ? "stop.fill" : "ellipsis")
                insertButton.isEnabled = hasFullAccess && session.phase == .recording
                insertButton.accessibilityHint = "Stops this recording and prepares text to insert."
                discardButton.isHidden = !hasFullAccess
                if session.phase == .recording {
                    instruction.text = hasFullAccess ? "Stop when you’re done. Your text will be ready to insert."
                        : "Stop in Sayso or the Live Activity. Full Access enables keyboard controls."
                } else {
                    instruction.text = "Your microphone is off. Preparing your text to insert."
                }
                return
            }
            guard let payload = try handoff.latest() else {
                nextState = .empty
                visiblePayload = nil
                preview.text = "Your words, ready here."
                instruction.text = "Start Dictate in another app in Sayso, or send a finished result."
                insertButton.isEnabled = false
                insertButton.configuration?.title = "Insert"
                return
            }
            visiblePayload = payload
            let consumed = UserDefaults.standard.string(forKey: consumedKey) == payload.consumptionIdentifier
            nextState = .result(payload.consumptionIdentifier, consumed: consumed)
            preview.text = payload.text
            instruction.text = consumed ? "Inserted. Send another result from Sayso when you’re ready."
                : "Shared from Sayso · available for 10 minutes"
            insertButton.isEnabled = !consumed
            insertButton.configuration?.title = consumed ? "Inserted" : "Insert"
            insertButton.configuration?.image = UIImage(systemName: consumed ? "checkmark" : "arrow.up.doc")
        } catch {
            visiblePayload = nil
            preview.text = "Send a result from Sayso."
            instruction.text = "Keyboard sharing isn’t available. Your typing still works."
            insertButton.isEnabled = false
            insertButton.configuration?.title = "Insert"
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
        // information without retaining an old recording snapshot, moving keys,
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

    @objc private func insertSharedText() {
        if let session = visibleSession {
            sendControl(.stop, sessionID: session.id)
            return
        }
        guard let shown = visiblePayload else { return }
        do {
            guard let latest = try handoff.latest(), latest == shown,
                  UserDefaults.standard.string(forKey: consumedKey) != latest.consumptionIdentifier else {
                refreshHandoff()
                return
            }
            // No clipboard read, automatic insertion, or host-context collection.
            textDocumentProxy.insertText(latest.text)
            UserDefaults.standard.set(latest.consumptionIdentifier, forKey: consumedKey)
            refreshHandoff()
            UIAccessibility.post(notification: .announcement, argument: "Text inserted")
        } catch { refreshHandoff() }
    }

    @objc private func discardRecording() {
        guard let session = visibleSession else { return }
        sendControl(.cancel, sessionID: session.id)
    }

    private func sendControl(_ action: KeyboardRecordingSessionStore.Action, sessionID: UUID) {
        guard hasFullAccess else { refreshHandoff(); return }
        do {
            try recordingSessions.send(action, sessionID: sessionID)
            insertButton.isEnabled = false
            instruction.text = action == .stop ? "Finishing your words…" : "Discarding recording…"
            revealHandoffContent([instruction])
        } catch {
            refreshHandoff()
            instruction.text = error.localizedDescription
        }
    }

    private func makeKeys() {
        keyRowHeightConstraints.removeAll()
        for row in keys.arrangedSubviews { keys.removeArrangedSubview(row); row.removeFromSuperview() }
        let rows: [[Character]]
        if usesSymbols {
            rows = [Array("[]{}#%^*+="), Array("_\\|~<>€£¥•"), Array(".,?!'`")]
        } else if usesNumbers {
            rows = [Array("1234567890"), Array("-/:;()$&@\""), Array(".,?!'")]
        } else {
            rows = [Array("qwertyuiop"), Array("asdfghjkl"), Array("zxcvbnm")]
        }

        for (index, characters) in rows.enumerated() {
            let row = makeRow()
            if index == 2 && !usesNumbers {
                let shift = key(title: "⇧", label: "Shift", identifier: "keyboardShiftButton")
                shift.backgroundColor = isShifted ? KeyboardPalette.accent : KeyboardPalette.utilityKey
                shift.setTitleColor(isShifted ? KeyboardPalette.onAccent : KeyboardPalette.ink, for: .normal)
                shift.addTarget(self, action: #selector(toggleShift), for: .touchUpInside)
                row.addArrangedSubview(shift)
            } else if index == 2 {
                let symbols = key(title: usesSymbols ? "123" : "#+=", label: usesSymbols ? "Numbers" : "More symbols", identifier: "keyboardSymbolsButton")
                symbols.backgroundColor = KeyboardPalette.utilityKey
                symbols.addTarget(self, action: #selector(toggleSymbols), for: .touchUpInside)
                row.addArrangedSubview(symbols)
            }
            for character in characters {
                let value = String(character)
                let title = isShifted && !usesNumbers ? value.uppercased() : value
                let button = key(title: title, label: title, identifier: "keyboardKey-\(value)")
                button.addAction(UIAction { [weak self] _ in self?.type(title) }, for: .touchUpInside)
                row.addArrangedSubview(button)
            }
            if index == 2 {
                let delete = key(title: "⌫", label: "Delete", identifier: "keyboardDeleteButton")
                delete.backgroundColor = KeyboardPalette.utilityKey
                delete.addTarget(self, action: #selector(deleteOnce), for: .touchUpInside)
                delete.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(repeatDelete(_:))))
                row.addArrangedSubview(delete)
            }
            keys.addArrangedSubview(row)
        }

        let bottom = makeRow()
        bottom.distribution = .fill
        let numbers = key(title: usesNumbers ? "ABC" : "123", label: usesNumbers ? "Letters" : "Numbers and punctuation", identifier: "keyboardNumbersButton")
        numbers.backgroundColor = KeyboardPalette.utilityKey
        numbers.addTarget(self, action: #selector(toggleNumbers), for: .touchUpInside)
        numbers.widthAnchor.constraint(equalToConstant: 47).isActive = true
        bottom.addArrangedSubview(numbers)

        var nextConfiguration = UIButton.Configuration.plain()
        nextConfiguration.image = UIImage(systemName: "globe")
        nextButton.configuration = nextConfiguration
        nextButton.backgroundColor = KeyboardPalette.utilityKey
        nextButton.tintColor = KeyboardPalette.ink
        nextButton.layer.cornerRadius = 6
        nextButton.accessibilityLabel = "Next keyboard"
        nextButton.accessibilityIdentifier = "keyboardNextButton"
        nextButton.removeTarget(nil, action: nil, for: .allEvents)
        nextButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        if !nextButton.constraints.contains(where: { $0.firstAttribute == .width }) {
            nextButton.widthAnchor.constraint(equalToConstant: 42).isActive = true
        }
        bottom.addArrangedSubview(nextButton)

        let space = key(title: "space", label: "Space", identifier: "keyboardSpaceButton")
        space.addAction(UIAction { [weak self] _ in self?.type(" ") }, for: .touchUpInside)
        bottom.addArrangedSubview(space)
        let enter = key(title: "return", label: "Return", identifier: "keyboardReturnButton")
        enter.backgroundColor = KeyboardPalette.utilityKey
        enter.widthAnchor.constraint(equalToConstant: 78).isActive = true
        enter.addAction(UIAction { [weak self] _ in self?.type("\n") }, for: .touchUpInside)
        bottom.addArrangedSubview(enter)
        keys.addArrangedSubview(bottom)
    }

    private var preferredKeyboardHeight: CGFloat {
        let accessibility = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        // Compact: 6pt top + 44pt header + 6pt gap + four 36pt rows +
        // three 4pt gaps + 12pt bottom allowance = 224pt. AX reserves
        // 14pt more for the scaled preview/status and action labels.
        // Portrait retains its larger key rows and stacked AX header.
        if usesCompactHeight { return accessibility ? 238 : 224 }
        return accessibility ? 450 : 326
    }

    private var usesCompactHeight: Bool {
        traitCollection.verticalSizeClass == .compact ||
            view.window?.windowScene?.effectiveGeometry.interfaceOrientation.isLandscape == true
    }

    private func makeRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 5
        let height = row.heightAnchor.constraint(equalToConstant: usesCompactHeight ? 36 : 42)
        height.isActive = true
        keyRowHeightConstraints.append(height)
        return row
    }

    private func key(title: String, label: String, identifier: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(KeyboardPalette.ink, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: title.count == 1 ? 21 : 15)
        button.backgroundColor = KeyboardPalette.key
        button.layer.cornerRadius = 6
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.10
        button.layer.shadowRadius = 0
        button.layer.shadowOffset = .init(width: 0, height: 1)
        button.accessibilityLabel = label
        button.accessibilityIdentifier = identifier
        return button
    }

    private func type(_ text: String) {
        textDocumentProxy.insertText(text)
        if isShifted && !usesNumbers { isShifted = false; makeKeys() }
    }

    @objc private func toggleShift() { isShifted.toggle(); makeKeys() }
    @objc private func toggleNumbers() { usesNumbers.toggle(); usesSymbols = false; makeKeys() }
    @objc private func toggleSymbols() { usesSymbols.toggle(); makeKeys() }
    @objc private func deleteOnce() { textDocumentProxy.deleteBackward() }
    @objc private func repeatDelete(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            deleteOnce()
            deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.deleteOnce() }
            }
        } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            stopRepeatedDeletion()
        }
    }
    private func stopRepeatedDeletion() { deleteTimer?.invalidate(); deleteTimer = nil }
}

// The keyboard is a separate process, so keep these appearance tokens aligned
// with SaysoTheme and ActivityPalette without importing app-only views.
private enum KeyboardPalette {
    static let canvas = dynamic(light: 0xF8F6F2, dark: 0x141218)
    static let ink = dynamic(light: 0x261F2F, dark: 0xF5F0FA)
    static let secondaryInk = dynamic(light: 0x6D6674, dark: 0xB8AEBD)
    static let accent = dynamic(light: 0x503968, dark: 0xCEB8F2)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x261F2F)
    static let key = dynamic(light: 0xFFFFFF, dark: 0x343039)
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
