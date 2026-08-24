import Foundation

public enum DictationSpacing {
    nonisolated(unsafe) public static var pendingLeadingSpace = false

    private static let noLeadingSpace: Set<Character> = [
        ",", ".", "!", "?", ":", ";", ")", "]", "}", "…", "'", "%",
    ]

    public static func reset() {
        pendingLeadingSpace = false
    }

    public static func preview(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if pendingLeadingSpace && !suppressesLeadingSpace(trimmed) {
            return " " + trimmed
        }
        return trimmed
    }

    public static func textToType(_ raw: String) -> String {
        let out = preview(raw)
        guard !out.isEmpty else { return "" }
        pendingLeadingSpace = needsSpaceAfter(out)
        return out
    }

    public static func markCommitted(_ text: String) {
        pendingLeadingSpace = needsSpaceAfter(text)
    }

    public static func punctuationToType(_ character: String) -> String {
        guard !character.isEmpty else { return "" }
        var out = character
        if pendingLeadingSpace && !suppressesLeadingSpace(character) {
            out = " " + character
        }
        pendingLeadingSpace = needsSpaceAfter(character)
        return out
    }

    public static func noteKeyPress(keyCode: UInt16) {
        switch keyCode {
        case 36, 48, 49, 51, 53, 117, 123, 124, 125, 126:
            pendingLeadingSpace = false
        default:
            pendingLeadingSpace = true
        }
    }

    private static func suppressesLeadingSpace(_ text: String) -> Bool {
        guard let first = text.first else { return true }
        return noLeadingSpace.contains(first)
    }

    private static func needsSpaceAfter(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        if last.isWhitespace { return false }
        switch last {
        case "(", "[", "{", "/", "\\", "_", "-":
            return false
        default:
            return true
        }
    }
}
