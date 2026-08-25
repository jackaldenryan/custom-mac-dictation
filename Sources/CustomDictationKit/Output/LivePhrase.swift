import Foundation

public enum LivePhrase {
    nonisolated(unsafe) public static var displayed = ""
    nonisolated(unsafe) public static var pendingLeadSpace = false

    public static func show(_ text: String) {
        apply(spaced(text))
    }

    public static func commit(_ text: String) {
        apply(spaced(text))
        if !displayed.isEmpty { pendingLeadSpace = true }
        displayed = ""
    }

    public static func discard() {
        apply("")
        displayed = ""
    }

    public static func keepAndUnhighlight() {
        guard !displayed.isEmpty else { return }
        pendingLeadSpace = true
        displayed = ""
    }

    private static func spaced(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        if pendingLeadSpace, text.first?.isWhitespace != true {
            return " " + text
        }
        return text
    }

    private static func apply(_ text: String) {
        if displayed == text { return }
        if keepsTrailingPunctuation(displayed: displayed, incoming: text) {
            return
        }
        if displayed.isEmpty {
            Typist.typeText(text)
        } else if folds(text).hasPrefix(folds(displayed)) {
            Typist.typeText(String(text.dropFirst(displayed.count)))
        } else {
            Typist.deleteBackward(times: displayed.count)
            Typist.typeText(text)
        }
        displayed = text
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
