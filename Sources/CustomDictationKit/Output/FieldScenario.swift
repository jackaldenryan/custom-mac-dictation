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

public enum LiveInsertPath: String, Equatable, Sendable {
    case ax
    case hid
    case imk
    case skipped
}

public struct FieldProfile: Equatable, Sendable {
    public var axWrite: Bool
    public var unicodeReplacesSelection: Bool
    public var stubFocused: Bool
    public var hasClient: Bool

    public static func profile(_ box: FieldBox) -> FieldProfile {
        switch box {
        case .notes, .chromeURL:
            return FieldProfile(axWrite: true, unicodeReplacesSelection: true, stubFocused: false, hasClient: true)
        case .googleSearch, .zoom:
            return FieldProfile(axWrite: false, unicodeReplacesSelection: false, stubFocused: false, hasClient: true)
        case .slack, .cursorEditor, .openCode:
            return FieldProfile(axWrite: false, unicodeReplacesSelection: false, stubFocused: false, hasClient: true)
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
    public let box: FieldBox
    private var markStart: Int?
    private var stubText = ""

    public var profile: FieldProfile { FieldProfile.profile(box) }

    public init(box: FieldBox, text: String = "", loc: Int? = nil, len: Int = 0) {
        self.box = box
        self.text = text
        self.loc = loc ?? (text as NSString).length
        self.len = len
    }

    public func apply(shaped: String, keepSelected: Bool, useInputMethod: Bool) {
        let p = profile
        if p.stubFocused {
            intoStub = true
            lastPath = .skipped
            displayed = ""
            return
        }
        if useInputMethod {
            if !p.hasClient {
                lastPath = .skipped
                displayed = ""
                return
            }
            replaceMark(with: shaped, select: keepSelected && !shaped.isEmpty)
            lastPath = .imk
            displayed = shaped
            if keepSelected { liveVisible = true }
            return
        }
        if p.axWrite {
            replaceMark(with: shaped, select: keepSelected && !shaped.isEmpty)
            lastPath = .ax
            displayed = shaped
            if keepSelected { liveVisible = true }
            return
        }
        hidReplace(shaped)
        lastPath = .hid
        displayed = shaped
        if keepSelected { liveVisible = true }
    }

    public func finishIfNeeded() {
        guard lastPath == .ax else { return }
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
        } else if folds(text).hasPrefix(folds(displayed)) {
            unicodeInsert(String(text.dropFirst(displayed.count)), replaceSelection: false)
        } else {
            flickered = true
            deleteBackward((displayed as NSString).length)
            unicodeInsert(text, replaceSelection: false)
        }
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
