import ApplicationServices
import Foundation

public enum InsertionContext {
    public static func isSentenceStart() -> Bool {
        if LivePhrase.pendingLeadSpace { return false }
        guard AXIsProcessTrusted() else { return true }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused
        else { return true }

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String
        else { return true }

        var rangeRef: CFTypeRef?
        var location = value.utf16.count
        if AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let axRange = rangeRef {
            var cfRange = CFRange()
            if AXValueGetValue(axRange as! AXValue, .cfRange, &cfRange) {
                location = max(0, cfRange.location)
            }
        }

        return leadingCharacterImpliesSentenceStart(value, utf16Location: location)
    }

    public static func leadingCharacterImpliesSentenceStart(_ value: String, utf16Location: Int) -> Bool {
        guard utf16Location > 0 else { return true }
        let utf16 = Array(value.utf16)
        let end = min(utf16Location, utf16.count)
        var i = end
        while i > 0 {
            i -= 1
            let scalar = UnicodeScalar(utf16[i]) ?? UnicodeScalar(32)!
            let ch = Character(scalar)
            if ch.isWhitespace || ch == "\n" || ch == "\r" { continue }
            return ch == "." || ch == "?" || ch == "!" || ch == "…"
        }
        return true
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
        }
        return decapitalizeIfNeeded(t)
    }

    private static func decapitalizeIfNeeded(_ text: String) -> String {
        guard let first = text.first, first.isUppercase else { return text }
        let rest = text.dropFirst()
        if first == "I", rest.isEmpty || rest.first == "'" || rest.first == "’" || rest.first == " " {
            return text
        }
        return String(first).localizedLowercase + rest
    }
}
