import AppKit
import Foundation

public enum LivePhrase {
    nonisolated(unsafe) public static var displayed = ""
    nonisolated(unsafe) public static var pendingLeadSpace = false
    nonisolated(unsafe) public static var useInputMethodOverride: Bool?
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
        rememberTail(displayed)
        displayed = ""
        phrasePath = nil
    }

    public static func discard() {
        apply("", keepSelected: false)
        displayed = ""
        phrasePath = nil
        if !usesInputMethod() {
            FieldEditor.clearLive()
        }
    }

    public static func noteCommand() {
        pendingLeadSpace = true
        lastTypedTail = nil
        lastTypedApp = nil
    }

    public static func keepAndUnhighlight() {
        guard !displayed.isEmpty else { return }
        finishCommittedMark()
        pendingLeadSpace = true
        rememberTail(displayed)
        displayed = ""
        phrasePath = nil
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
        if PlaygroundTarget.shared.isActive { return "playground:\(PlaygroundTarget.shared.box.rawValue)" }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
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
            isPartial: isPartial,
            pendingLeadSpace: pendingLeadSpace,
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
        if displayed.isEmpty { phrasePath = nil }
        if PhrasePathLock.mayTryAX(phrasePath: phrasePath) {
            if FieldEditor.replaceLive(with: text, select: keepSelected && !text.isEmpty) {
                lastInsertPath = .ax
                phrasePath = .ax
                displayed = text
                return
            }
            if phrasePath == .ax, !displayed.isEmpty {
                // A native field stopped taking AX writes mid-phrase. The
                // failed write restored the selection, so our live text is
                // still selected: typing replaces exactly that, then this
                // phrase continues with HID at the caret it leaves.
                DiagnosticLog.line("AX live write failed mid-phrase; finishing phrase with keystrokes")
                if text.isEmpty {
                    Typist.deleteSelection()
                } else {
                    Typist.typeText(text, preferAX: false)
                }
                Typist.releaseModifiers()
                lastInsertPath = .hid
                phrasePath = .hid
                displayed = text
                return
            }
        }
        guard hidFallbackAllowed() else {
            DiagnosticLog.line("Live phrase skipped; front app has nowhere to type")
            lastInsertPath = .skipped
            displayed = ""
            return
        }
        hidReplace(text)
        lastInsertPath = .hid
        phrasePath = .hid
        displayed = text
    }

    /// HID fallback must not type where no text can land. Browsers and
    /// Electron apps need HID (their fields are often invisible to AX), but
    /// Finder has no insertion point at all and the Notes sidebar is not a
    /// text field, so dictating there renames files or mangles the sidebar.
    /// The IMK path already skips these via client availability; this is the
    /// AX/HID equivalent.
    private static func hidFallbackAllowed() -> Bool {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if front == "com.apple.finder" { return false }
        if front == "com.apple.Notes", FieldEditor.focusedElementIsPresentButNotEditable() { return false }
        return true
    }

    private static func hidReplace(_ text: String) {
        if displayed.isEmpty {
            // No AX-driven delete of a "selection" first: web engines report
            // stale or parent-level selections, and a stray backspace eats a
            // character of earlier text. A real selection is replaced by the
            // typed text anyway, as with the shipped release.
            Typist.typeText(text, preferAX: false)
        } else {
            // Suffix-diff revision: a recognizer correction usually changes
            // the tail ("reciept" -> "receipt"), so keep the shared prefix
            // and only delete/retype the differing suffix instead of the
            // whole phrase. Fewer key events means faster Slack updates and
            // less flicker.
            let keep = commonPrefixKeepCount(displayed, text)
            if keep == displayed.count, text.count >= displayed.count {
                Typist.typeText(String(text.dropFirst(displayed.count)), preferAX: false)
            } else {
                Typist.deleteBackward(times: displayed.count - keep)
                Typist.typeText(String(text.dropFirst(keep)), preferAX: false)
            }
        }
        Typist.releaseModifiers()
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
