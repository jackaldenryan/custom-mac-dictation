import Foundation

public enum LivePhrase {
    nonisolated(unsafe) public static var displayed = ""
    nonisolated(unsafe) public static var pendingLeadSpace = false
    nonisolated(unsafe) public static var lastTypedAt = Date.distantPast
    nonisolated(unsafe) private static var phraseIsMidSentence = false
    nonisolated(unsafe) private static var phraseSnapshot: CaretSnapshot?

    public static func show(_ text: String) {
        guard let out = shaped(text, isPartial: true) else { return }
        apply(out, keepSelected: true)
    }

    public static func commit(_ text: String) {
        guard let out = shaped(text, isPartial: false) else { return }
        apply(out, keepSelected: false)
        FieldEditor.finishLive()
        if !displayed.isEmpty { pendingLeadSpace = true }
        displayed = ""
        lastTypedAt = Date()
    }

    public static func discard() {
        apply("", keepSelected: false)
        displayed = ""
        FieldEditor.clearLive()
    }

    public static func noteCommand() {
        lastTypedAt = Date()
        pendingLeadSpace = true
    }

    public static func keepAndUnhighlight() {
        guard !displayed.isEmpty else { return }
        _ = FieldEditor.replaceLive(with: displayed, select: false)
        pendingLeadSpace = true
        displayed = ""
    }

    private static func shaped(_ text: String, isPartial: Bool) -> String? {
        if displayed.isEmpty {
            phraseSnapshot = InsertionContext.snapshot()
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
            lonePunctuationDelay: SettingsStore.shared.settings.lonePunctuationDelaySeconds,
            isLonePunctuation: TranscriptNormalizer.isLonePunctuation(text),
            midSentence: phraseIsMidSentence,
            snapshot: phraseSnapshot
        )
        return PostProcessor.process(input, settings: SettingsStore.shared.settings)
    }

    private static func apply(_ text: String, keepSelected: Bool) {
        if displayed == text { return }
        if keepsTrailingPunctuation(displayed: displayed, incoming: text) {
            return
        }
        if FieldEditor.focusedLooksLikeStub() {
            DiagnosticLog.line("Live phrase skipped; focused field is a stub")
            displayed = ""
            return
        }
        if FieldEditor.replaceLive(with: text, select: keepSelected && !text.isEmpty) {
            displayed = text
            return
        }
        hidReplace(text)
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

    private static func keepsTrailingPunctuation(displayed: String, incoming: String) -> Bool {
        let have = folds(displayed)
        let next = folds(incoming)
        guard have.hasPrefix(next), have.count > next.count else { return false }
        let extra = have.dropFirst(next.count)
        return extra.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0) || $0.properties.isWhitespace
        }
    }

    private static func folds(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
    }
}
