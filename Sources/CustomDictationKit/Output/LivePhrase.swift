import Foundation

public enum LivePhrase {
    nonisolated(unsafe) public static var displayed = ""
    nonisolated(unsafe) public static var pendingLeadSpace = false
    nonisolated(unsafe) public static var lastTypedAt = Date.distantPast
    nonisolated(unsafe) public static var useInputMethodOverride: Bool?
    nonisolated(unsafe) private static var phraseIsMidSentence = false
    nonisolated(unsafe) private static var phraseSnapshot: CaretSnapshot?
    nonisolated(unsafe) private static var lastInsertPath = LiveInsertPath.skipped

    public static func usesInputMethod() -> Bool {
        if DictationTextInput.override != nil { return true }
        if let override = useInputMethodOverride { return override }
        return SettingsStore.shared.settings.useInputMethod
    }

    public static func show(_ text: String) {
        guard let out = shaped(text, isPartial: true) else { return }
        apply(out, keepSelected: true)
    }

    public static func commit(_ text: String) {
        guard let out = shaped(text, isPartial: false) else { return }
        apply(out, keepSelected: false)
        finishCommittedMark()
        if !displayed.isEmpty { pendingLeadSpace = true }
        displayed = ""
        lastTypedAt = Date()
    }

    public static func discard() {
        apply("", keepSelected: false)
        displayed = ""
        if !usesInputMethod() {
            FieldEditor.clearLive()
        }
    }

    public static func noteCommand() {
        lastTypedAt = Date()
        pendingLeadSpace = true
    }

    public static func keepAndUnhighlight() {
        guard !displayed.isEmpty else { return }
        finishCommittedMark()
        pendingLeadSpace = true
        displayed = ""
    }

    private static func finishCommittedMark() {
        if PlaygroundTarget.shared.isActive {
            PlaygroundTarget.shared.collapseLive()
            return
        }
        if usesInputMethod() {
            DictationTextInput.current.unmarkText()
            return
        }
        if LiveCommitPolicy.shouldFinishAXMark(lastInsertPath) {
            FieldEditor.finishLive()
        }
    }

    private static func shaped(_ text: String, isPartial: Bool) -> String? {
        if displayed.isEmpty {
            if usesInputMethod() {
                phraseSnapshot = DictationTextInput.current.caretSnapshot() ?? InsertionContext.snapshot()
            } else {
                phraseSnapshot = InsertionContext.snapshot()
            }
            if let snap = phraseSnapshot {
                phraseIsMidSentence = !InsertionContext.impliesSentenceStart(snap)
            } else {
                phraseIsMidSentence = pendingLeadSpace
            }
        }
        let input = PostProcessInput(
            text: text,
            isPartial: isPartial,
            pendingLeadSpace: pendingLeadSpace,
            lastTypedAge: Date().timeIntervalSince(lastTypedAt),
            lonePunctuationDelay: SettingsStore.shared.settings.effectiveLonePunctuationDelay,
            isLonePunctuation: TranscriptNormalizer.isLonePunctuation(text),
            midSentence: phraseIsMidSentence,
            snapshot: phraseSnapshot
        )
        return PostProcessor.process(input, settings: SettingsStore.shared.settings)
    }

    private static func apply(_ text: String, keepSelected: Bool) {
        if displayed == text { return }
        if PlaygroundTarget.shared.isActive {
            lastInsertPath = PlaygroundTarget.shared.apply(
                shaped: text,
                keepSelected: keepSelected,
                isPartial: keepSelected && !text.isEmpty
            )
            displayed = lastInsertPath == .skipped ? "" : text
            return
        }
        if usesInputMethod() {
            applyInputMethod(text, keepSelected: keepSelected)
            return
        }
        applyAXHid(text, keepSelected: keepSelected)
    }

    private static func applyInputMethod(_ text: String, keepSelected: Bool) {
        let client = DictationTextInput.current
        guard client.isAvailable else {
            DiagnosticLog.line("Live phrase skipped; no text input client")
            displayed = ""
            return
        }
        if keepSelected, !text.isEmpty {
            client.setMarkedText(text)
        } else {
            client.insertText(text)
        }
        lastInsertPath = .imk
        displayed = text
    }

    private static func applyAXHid(_ text: String, keepSelected: Bool) {
        if FieldEditor.focusedLooksLikeStub() {
            DiagnosticLog.line("Live phrase skipped; focused field is a stub")
            lastInsertPath = .skipped
            displayed = ""
            return
        }
        if FieldEditor.replaceLive(with: text, select: keepSelected && !text.isEmpty) {
            lastInsertPath = .ax
            displayed = text
            return
        }
        hidReplace(text)
        lastInsertPath = .hid
        displayed = text
    }

    private static func hidReplace(_ text: String) {
        if displayed.isEmpty {
            if FieldEditor.hasSelection() {
                Typist.deleteSelection()
            }
            Typist.typeText(text, preferAX: false)
        } else if folds(text).hasPrefix(folds(displayed)) {
            Typist.typeText(String(text.dropFirst(displayed.count)), preferAX: false)
        } else {
            Typist.deleteBackward(times: (displayed as NSString).length)
            Typist.typeText(text, preferAX: false)
        }
        Typist.releaseModifiers()
    }

    private static func folds(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
    }
}
