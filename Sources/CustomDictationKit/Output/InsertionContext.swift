import ApplicationServices
import Foundation

public struct CaretSnapshot: Equatable, Sendable {
    public var before: Character?
    public var secondBefore: Character?
    public var lastNonSpaceBefore: Character?
    public var lastNonSpaceIsAtLineStart: Bool
    public var after: Character?
    public var selectedLength: Int
    public var atStart: Bool

    public init(
        before: Character?,
        secondBefore: Character? = nil,
        lastNonSpaceBefore: Character? = nil,
        lastNonSpaceIsAtLineStart: Bool = false,
        after: Character?,
        selectedLength: Int,
        atStart: Bool
    ) {
        self.before = before
        self.secondBefore = secondBefore
        self.lastNonSpaceBefore = lastNonSpaceBefore
        self.lastNonSpaceIsAtLineStart = lastNonSpaceIsAtLineStart
        self.after = after
        self.selectedLength = selectedLength
        self.atStart = atStart
    }
}

public enum InsertionContext {
    public static func snapshot() -> CaretSnapshot? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused
        else { return nil }

        let ax = element as! AXUIElement
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String
        else { return nil }

        var location = value.utf16.count
        var length = 0
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(ax, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let axRange = rangeRef {
            var cfRange = CFRange()
            if AXValueGetValue(axRange as! AXValue, .cfRange, &cfRange) {
                location = max(0, cfRange.location)
                length = max(0, cfRange.length)
            }
        }
        return snapshot(in: value, utf16Location: location, utf16Length: length)
    }

    public static func snapshot(in value: String, utf16Location: Int, utf16Length: Int) -> CaretSnapshot {
        let utf16 = Array(value.utf16)
        let loc = min(max(0, utf16Location), utf16.count)
        let len = min(max(0, utf16Length), utf16.count - loc)
        let before: Character? = loc > 0 ? Character(UnicodeScalar(utf16[loc - 1]) ?? UnicodeScalar(32)!) : nil
        let secondBefore: Character? = loc > 1 ? Character(UnicodeScalar(utf16[loc - 2]) ?? UnicodeScalar(32)!) : nil
        var lastNonSpace: Character?
        var lastNonSpaceIndex: Int?
        var i = loc
        while i > 0 {
            i -= 1
            let ch = Character(UnicodeScalar(utf16[i]) ?? UnicodeScalar(32)!)
            if !ch.isWhitespace, ch != "\n", ch != "\r" {
                lastNonSpace = ch
                lastNonSpaceIndex = i
                break
            }
        }
        var lastNonSpaceIsAtLineStart = lastNonSpace != nil
        if let idx = lastNonSpaceIndex {
            var j = idx
            while j > 0 {
                j -= 1
                let ch = Character(UnicodeScalar(utf16[j]) ?? UnicodeScalar(32)!)
                if ch == "\n" || ch == "\r" { break }
                if !ch.isWhitespace {
                    lastNonSpaceIsAtLineStart = false
                    break
                }
            }
        }
        let afterIndex = loc + len
        let after: Character? = afterIndex < utf16.count ? Character(UnicodeScalar(utf16[afterIndex]) ?? UnicodeScalar(32)!) : nil
        return CaretSnapshot(
            before: before,
            secondBefore: secondBefore,
            lastNonSpaceBefore: lastNonSpace,
            lastNonSpaceIsAtLineStart: lastNonSpaceIsAtLineStart,
            after: after,
            selectedLength: len,
            atStart: loc == 0
        )
    }

    public static func isSentenceStart() -> Bool {
        if let snap = snapshot() {
            return impliesSentenceStart(snap)
        }
        if LivePhrase.pendingLeadSpace { return false }
        return true
    }

    public static func impliesSentenceStart(_ snap: CaretSnapshot) -> Bool {
        guard let ch = snap.lastNonSpaceBefore else { return true }
        return ch == "." || ch == "?" || ch == "!" || ch == "…"
    }

    public static func leadingCharacterImpliesSentenceStart(_ value: String, utf16Location: Int) -> Bool {
        impliesSentenceStart(snapshot(in: value, utf16Location: utf16Location, utf16Length: 0))
    }
}

public enum FieldFit {
    public static func needsLeadSpace(_ body: String, snapshot: CaretSnapshot?, pendingLeadSpace: Bool) -> Bool {
        guard let first = body.first, !first.isWhitespace else { return false }
        if attachesLeft(first) { return false }
        if let snapshot {
            if snapshot.selectedLength > 0 { return false }
            if snapshot.atStart { return false }
            guard let before = snapshot.before else { return false }
            if before.isWhitespace { return false }
            if opensRight(before) {
                if isQuote(before), let prev = snapshot.secondBefore, prev.isLetter || prev.isNumber {
                    return true
                }
                return false
            }
            if joinsRight(before) { return false }
            return true
        }
        return pendingLeadSpace
    }

    private static func attachesLeft(_ ch: Character) -> Bool {
        ",.!?:;)]}'\"”’/".contains(ch)
    }

    private static func opensRight(_ ch: Character) -> Bool {
        "([{\"'“‘".contains(ch)
    }

    private static func joinsRight(_ ch: Character) -> Bool {
        ch == "/" || ch == "-"
    }

    private static func isQuote(_ ch: Character) -> Bool {
        "\"'“”‘’".contains(ch)
    }
}

public enum SentenceFit {
    public static func sentenceStart(_ text: String) -> String {
        capitalizeIfNeeded(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func midSentence(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return text }
        if t.hasSuffix("..."), t.count > 3 {
            t = String(t.dropLast(3)).trimmingCharacters(in: .whitespaces)
        } else if t.hasSuffix("."), !t.hasSuffix("..") {
            t = String(t.dropLast()).trimmingCharacters(in: .whitespaces)
        } else if t.hasSuffix("?"), t.count >= 2, t.dropLast().last?.isLetter == true || t.dropLast().last?.isNumber == true {
            t = String(t.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return decapitalizeIfNeeded(t)
    }

    private static func capitalizeIfNeeded(_ text: String) -> String {
        guard let first = text.first, first.isLetter, first.isLowercase else { return text }
        return String(first).localizedUppercase + text.dropFirst()
    }

    private static func decapitalizeIfNeeded(_ text: String) -> String {
        guard let first = text.first, first.isUppercase else { return text }
        let rest = text.dropFirst()
        if first == "I", rest.isEmpty || rest.first == "'" || rest.first == "’" || rest.first == " " {
            return text
        }
        if let second = rest.first, second.isUppercase {
            return text
        }
        return String(first).localizedLowercase + rest
    }
}
