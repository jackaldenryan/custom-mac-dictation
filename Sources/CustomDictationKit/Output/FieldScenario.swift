import Foundation

public enum FieldBox: String, CaseIterable, Sendable, Identifiable {
    case notes
    case chromeURL
    case googleSearch
    case slack
    case cursorEditor
    case cursorStub
    case openCode
    case zoom
    case finder
    case notesSidebar

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notes: return "Notes"
        case .chromeURL: return "Chrome URL bar"
        case .googleSearch: return "Google search"
        case .slack: return "Slack"
        case .cursorEditor: return "Cursor editor"
        case .cursorStub: return "Cursor stub"
        case .openCode: return "OpenCode"
        case .zoom: return "Zoom chat"
        case .finder: return "Finder"
        case .notesSidebar: return "Notes sidebar"
        }
    }
}

public struct FieldProfile: Equatable, Sendable {
    public var axWrite: Bool
    public var unicodeReplacesSelection: Bool
    public var stubFocused: Bool
    public var hasClient: Bool
    /// Web engine (Electron/Chromium/WebKit): an AX text write reports
    /// success, the text never lands, but the caret/selection move does, to
    /// a stale AX-reported position. AXWritePolicy keeps the app from ever
    /// trying; `probeAXInWebEngines` replays the pre-fix behavior.
    public var webEngine: Bool = false

    public static func profile(_ box: FieldBox) -> FieldProfile {
        switch box {
        case .notes:
            return FieldProfile(axWrite: true, unicodeReplacesSelection: true, stubFocused: false, hasClient: true)
        case .chromeURL:
            // Chrome is a web engine: AXWritePolicy sends it to HID only.
            return FieldProfile(axWrite: false, unicodeReplacesSelection: true, stubFocused: false, hasClient: true, webEngine: true)
        case .googleSearch, .zoom:
            return FieldProfile(axWrite: false, unicodeReplacesSelection: false, stubFocused: false, hasClient: true, webEngine: true)
        case .slack, .cursorEditor, .openCode:
            return FieldProfile(axWrite: false, unicodeReplacesSelection: false, stubFocused: false, hasClient: true, webEngine: true)
        case .cursorStub:
            return FieldProfile(axWrite: false, unicodeReplacesSelection: false, stubFocused: true, hasClient: false)
        case .finder, .notesSidebar:
            return FieldProfile(axWrite: false, unicodeReplacesSelection: false, stubFocused: false, hasClient: false)
        }
    }
}

public final class SimulatedField: @unchecked Sendable {
    public var text: String
    public var loc: Int
    public var len: Int
    public var flickered = false
    public var intoStub = false
    public var liveVisible = false
    public var lastPath = LiveInsertPath.skipped
    public var displayed = ""
    /// Keystroke estimate for the HID path (inserted + deleted UTF-16
    /// units). AX writes are atomic and count nothing: that gap is the
    /// performance story this measures (fewer events = faster Slack).
    public var insertedUnits = 0
    public var deletedUnits = 0
    public let box: FieldBox
    /// Replays the pre-fix local build, which tried an AX write in every app
    /// before falling back to HID. Only for the regression test.
    public var probeAXInWebEngines = false
    /// Caret position a web engine reports over AX: one update behind.
    private var axReportedLoc: Int
    private var markStart: Int?
    private var stubText = ""

    public var profile: FieldProfile { FieldProfile.profile(box) }

    public init(box: FieldBox, text: String = "", loc: Int? = nil, len: Int = 0) {
        self.box = box
        self.text = text
        self.loc = loc ?? (text as NSString).length
        self.len = len
        self.axReportedLoc = self.loc
    }

    public func apply(shaped: String, keepSelected: Bool, forceHID: Bool = false) {
        let p = profile
        if p.stubFocused {
            intoStub = true
            lastPath = .skipped
            displayed = ""
            return
        }
        // Mirrors LivePhrase.hidFallbackAllowed: skip apps with nowhere to
        // type (Finder, Notes sidebar). The release-HID model (forceHID)
        // keeps the v0.1.39 behavior for comparison.
        if !forceHID, !p.hasClient {
            lastPath = .skipped
            displayed = ""
            return
        }
        if p.axWrite, !forceHID {
            replaceMark(with: shaped, select: keepSelected && !shaped.isEmpty)
            lastPath = .ax
            rememberDisplayed(shaped, keepSelected: keepSelected)
            return
        }
        let caretBefore = loc
        if p.webEngine, probeAXInWebEngines, !forceHID {
            // Pre-fix FieldEditor.write: set the selection at the stale AX
            // caret, "write" (dropped), select the phrase length there, fail
            // the confirm, leave the selection moved. HID then types there.
            let n = (text as NSString).length
            let start = min(axReportedLoc, n)
            loc = start
            len = min((shaped as NSString).length, n - start)
        }
        hidReplace(shaped)
        lastPath = .hid
        rememberDisplayed(shaped, keepSelected: keepSelected)
        axReportedLoc = caretBefore
    }

    private func rememberDisplayed(_ shaped: String, keepSelected: Bool) {
        if keepSelected {
            displayed = shaped
            liveVisible = true
        } else {
            displayed = ""
            liveVisible = false
        }
    }

    public func finishIfNeeded() {
        guard LiveCommitPolicy.shouldFinishAXMark(lastPath) else { return }
        if let start = markStart {
            loc = start + (displayed as NSString).length
            len = 0
            markStart = nil
        }
    }

    public func hidInsertIntoSelection(_ s: String) {
        unicodeInsert(s, replaceSelection: false)
    }

    private func hidReplace(_ text: String) {
        if displayed.isEmpty {
            unicodeInsert(text, replaceSelection: profile.unicodeReplacesSelection)
            return
        }
        // Same suffix-diff as LivePhrase.hidReplace: keep the shared prefix,
        // only delete/retype the differing suffix.
        let keepChars = LivePhrase.commonPrefixKeepCount(displayed, text)
        if keepChars == displayed.count, text.count >= displayed.count {
            unicodeInsert(String(text.dropFirst(displayed.count)), replaceSelection: false)
            return
        }
        flickered = true
        let shownUnits = (displayed as NSString).length
        let keepUnits = (String(displayed.prefix(keepChars)) as NSString).length
        deleteBackward(shownUnits - keepUnits)
        unicodeInsert(String(text.dropFirst(keepChars)), replaceSelection: false)
    }

    private func replaceMark(with s: String, select: Bool) {
        if markStart == nil { markStart = loc }
        let start = markStart ?? loc
        let ns = text as NSString
        let existing = max(0, loc - start)
        text = ns.replacingCharacters(in: NSRange(location: start, length: existing + len), with: s)
        markStart = start
        if select {
            loc = start
            len = (s as NSString).length
        } else {
            loc = start + (s as NSString).length
            len = 0
            markStart = nil
        }
    }

    private func unicodeInsert(_ s: String, replaceSelection: Bool) {
        if profile.stubFocused {
            intoStub = true
            stubText += s
            return
        }
        let ns = text as NSString
        insertedUnits += (s as NSString).length
        if replaceSelection, len > 0 {
            text = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: s)
            loc += (s as NSString).length
            len = 0
            return
        }
        text = ns.replacingCharacters(in: NSRange(location: loc, length: 0), with: s)
        loc += (s as NSString).length
        len = 0
    }

    private func deleteBackward(_ n: Int) {
        guard n > 0 else { return }
        deletedUnits += n
        let ns = text as NSString
        let start = max(0, loc - n)
        text = ns.replacingCharacters(in: NSRange(location: start, length: loc - start), with: "")
        loc = start
    }
}

private func folds(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\u{2019}", with: "'")
        .replacingOccurrences(of: "\u{2018}", with: "'")
        .replacingOccurrences(of: "\u{02BC}", with: "'")
}
