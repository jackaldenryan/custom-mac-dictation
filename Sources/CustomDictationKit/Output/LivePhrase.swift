import Foundation

public enum LivePhrase {
    nonisolated(unsafe) public static var displayed = ""

    public static func show(_ text: String) {
        apply(text)
    }

    public static func commit(_ text: String) {
        apply(text)
        displayed = ""
    }

    public static func discard() {
        apply("")
        displayed = ""
    }

    public static func keepAndUnhighlight() {
        guard !displayed.isEmpty else { return }
        displayed = ""
    }

    private static func apply(_ text: String) {
        if displayed == text { return }
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

    private static func folds(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
    }
}
