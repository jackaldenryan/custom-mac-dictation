import AppKit
import Foundation

public enum LivePhrase {
    nonisolated(unsafe) public static var displayed = ""
    nonisolated(unsafe) public static var pendingLeadSpace = false
    /// Test hook: when set, phrases go into this simulated field instead of
    /// the focused app, so CheckLogic can drive the real LivePhrase and
    /// Router with no AX or keystrokes. Always nil in the app.
    nonisolated(unsafe) public static var simulatedField: SimulatedField?
    nonisolated(unsafe) public static var output: any DictationOutput = SystemDictationOutput()
    nonisolated(unsafe) private static var phraseTarget: DictationTarget?
    nonisolated(unsafe) private static var cancelledForFocus = false
    nonisolated(unsafe) private static var phraseIsMidSentence = false
    nonisolated(unsafe) private static var phraseSnapshot: CaretSnapshot?
    nonisolated(unsafe) private static var lastInsertPath = LiveInsertPath.skipped
    /// Insertion method chosen for the phrase on screen; nil between phrases.
    /// Once a phrase types with HID it stays HID (see PhrasePathLock).
    nonisolated(unsafe) private static var phrasePath: LiveInsertPath?
    /// Last character dictation typed, and the app it went to. When AX can't
    /// read the caret, this decides capitalization (sentence start after our
    /// own "." / "?" / "!") and drops the lead space after an app switch.
    /// Cleared by commands.
    nonisolated(unsafe) private static var lastTypedTail: Character?
    nonisolated(unsafe) private static var lastTypedApp: String?

    public static func show(_ text: String) {
        let out = shaped(text)
        apply(out, keepSelected: true)
    }

    public static func commit(_ text: String) {
        let out = shaped(text)
        apply(out, keepSelected: false)
        finishCommittedMark()
        if !displayed.isEmpty { pendingLeadSpace = true }
        rememberTail(displayed)
        resetPhrase()
    }

    public static func discard() {
        apply("", keepSelected: false)
        resetPhrase()
        output.clearLive()
    }

    public static func noteCommand() {
        pendingLeadSpace = true
        lastTypedTail = nil
        lastTypedApp = nil
    }

    public static func keepAndUnhighlight() {
        finishCommittedMark()
        if !displayed.isEmpty { pendingLeadSpace = true }
        rememberTail(displayed)
        resetPhrase()
    }

    private static func rememberTail(_ typed: String) {
        guard lastInsertPath != .skipped,
              let last = typed.trimmingCharacters(in: .whitespacesAndNewlines).last
        else { return }
        lastTypedTail = last
        lastTypedApp = frontAppID()
    }

    /// Tail we typed, only if it went to the app that is frontmost now.
    private static func tailInFrontApp() -> Character? {
        guard let app = lastTypedApp, app == frontAppID() else { return nil }
        return lastTypedTail
    }

    private static func frontAppID() -> String {
        if let field = simulatedField { return "simulated:\(field.box.rawValue)" }
        return output.frontAppID
    }

    private static func finishCommittedMark() {
        if let field = simulatedField {
            field.finishIfNeeded()
            field.len = 0
            field.displayed = ""
            field.liveVisible = false
            return
        }
        if let target = phraseTarget {
            guard output.target() == target else {
                abandonForFocusChange()
                return
            }
            if LiveCommitPolicy.shouldFinishAXMark(lastInsertPath) {
                output.finishLive(target: target)
            }
        }
    }

    private static func shaped(_ spoken: String) -> String {
        let text = EmojiPhrases.replace(spoken)
        if displayed.isEmpty {
            phraseSnapshot = simulatedField == nil ? output.snapshot() : InsertionContext.snapshot()
            if let app = lastTypedApp, app != frontAppID() {
                // New app, new field: nothing we typed sits before this
                // caret, so no lead space.
                pendingLeadSpace = false
            }
            if let snap = phraseSnapshot {
                phraseIsMidSentence = !InsertionContext.impliesSentenceStart(snap)
            } else {
                let tail = tailInFrontApp()
                let endedSentence = tail.map { ".?!…".contains($0) } ?? false
                phraseIsMidSentence = pendingLeadSpace && !endedSentence
            }
        }
        let input = PostProcessInput(
            text: text,
            pendingLeadSpace: pendingLeadSpace,
            midSentence: phraseIsMidSentence,
            snapshot: phraseSnapshot
        )
        return DefaultPostProcess.apply(input)
    }

    private static func apply(_ text: String, keepSelected: Bool) {
        if let field = simulatedField {
            if displayed == text { return }
            field.apply(shaped: text, keepSelected: keepSelected)
            if !(keepSelected && !text.isEmpty) { field.finishIfNeeded() }
            lastInsertPath = field.lastPath
            displayed = lastInsertPath == .skipped ? "" : text
            return
        }
        applyAXHid(text, keepSelected: keepSelected)
    }

    private static func resetPhrase() {
        displayed = ""
        phrasePath = nil
        phraseTarget = nil
        cancelledForFocus = false
        lastInsertPath = .skipped
    }

    /// Never erase the old phrase after focus moves: that would send delete
    /// keys to a different control. Ignore the rest of this recognition
    /// phrase, even if focus returns, until commit/discard ends it.
    private static func abandonForFocusChange() {
        DiagnosticLog.line("Dictation phrase stopped: text destination changed or became unavailable")
        cancelledForFocus = true
        displayed = ""
        phrasePath = nil
        lastInsertPath = .skipped
        pendingLeadSpace = false
        lastTypedTail = nil
        lastTypedApp = nil
        output.clearLive()
    }

    private static func applyAXHid(_ text: String, keepSelected: Bool) {
        guard !cancelledForFocus else { return }
        let current = output.target()
        if let previous = phraseTarget, current != previous {
            abandonForFocusChange()
            return
        }
        guard let target = current else {
            lastInsertPath = .skipped
            return
        }
        // Validate even identical partials/finals, before the no-op shortcut.
        if displayed == text { return }
        phraseTarget = target
        if displayed.isEmpty { phrasePath = nil }
        if PhrasePathLock.mayTryAX(phrasePath: phrasePath) {
            if output.replaceLive(text, select: keepSelected && !text.isEmpty, target: target) {
                lastInsertPath = .ax
                phrasePath = .ax
                displayed = text
                return
            }
            // AX may have failed because the user switched focus during
            // the call. Do not interpret that as permission for HID fallback.
            guard output.target() == target else {
                abandonForFocusChange()
                return
            }
            if phrasePath == .ax, !displayed.isEmpty {
                let wrote = text.isEmpty
                    ? output.deleteBackward(1, target: target)
                    : output.typeText(text, target: target)
                guard wrote else { abandonForFocusChange(); return }
                lastInsertPath = .hid
                phrasePath = .hid
                displayed = text
                return
            }
        }
        guard hidReplace(text, target: target) else {
            abandonForFocusChange()
            return
        }
        lastInsertPath = .hid
        phrasePath = .hid
        displayed = text
    }

    private static func hidReplace(_ text: String, target: DictationTarget) -> Bool {
        if displayed.isEmpty {
            return output.typeText(text, target: target)
        }
        let keep = commonPrefixKeepCount(displayed, text)
        if keep < displayed.count {
            guard output.deleteBackward(displayed.count - keep, target: target) else { return false }
        }
        return output.typeText(String(text.dropFirst(keep)), target: target)
    }

    /// Characters of `displayed` shared with the start of `text`, comparing
    /// fold-equal (curly/straight quotes match). All folds in this codebase
    /// are 1:1 character mappings, so the count is exact in characters.
    public static func commonPrefixKeepCount(_ displayed: String, _ text: String) -> Int {
        var keep = 0
        var rest = text[...]
        for ch in displayed {
            guard let first = rest.first, folds(String(first)) == folds(String(ch)) else { break }
            keep += 1
            rest = rest.dropFirst()
        }
        return keep
    }

    private static func folds(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
    }
}
