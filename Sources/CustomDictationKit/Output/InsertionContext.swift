import ApplicationServices
import Foundation

public struct CaretSnapshot: Equatable, Sendable {
    public var before: Character?
    public var lastNonSpaceBefore: Character?
    public var after: Character?
    public var selectedLength: Int
    public var atStart: Bool

    public init(
        before: Character?,
        lastNonSpaceBefore: Character? = nil,
        after: Character?,
        selectedLength: Int,
        atStart: Bool
    ) {
        self.before = before
        self.lastNonSpaceBefore = lastNonSpaceBefore
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
        var lastNonSpace: Character?
        var i = loc
        while i > 0 {
            i -= 1
            let ch = Character(UnicodeScalar(utf16[i]) ?? UnicodeScalar(32)!)
            if !ch.isWhitespace, ch != "\n", ch != "\r" {
                lastNonSpace = ch
                break
            }
        }
        let afterIndex = loc + len
        let after: Character? = afterIndex < utf16.count ? Character(UnicodeScalar(utf16[afterIndex]) ?? UnicodeScalar(32)!) : nil
        return CaretSnapshot(
            before: before,
            lastNonSpaceBefore: lastNonSpace,
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
            if let before = snapshot.before, before.isWhitespace { return false }
            if let before = snapshot.before, opensRight(before) { return false }
            if let before = snapshot.before, ".?!…".contains(before) { return true }
            if let before = snapshot.before, before.isLetter || before.isNumber || before == "'" || before == "’" {
                return true
            }
            return false
        }
        return pendingLeadSpace
    }

    private static func attachesLeft(_ ch: Character) -> Bool {
        ",.!?:;)]}'\"”’/".contains(ch)
    }

    private static func opensRight(_ ch: Character) -> Bool {
        "([{\"'“‘".contains(ch)
    }
}

public enum SentenceFit {
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
