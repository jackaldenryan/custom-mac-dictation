import Foundation

public enum LivePhrase {
    nonisolated(unsafe) public static var displayed = ""
    nonisolated(unsafe) private static var highlighted = false

    public static func show(_ text: String) {
        apply(text, highlight: !text.isEmpty)
    }

    public static func commit(_ text: String) {
        apply(text, highlight: false)
        displayed = ""
        highlighted = false
    }

    public static func discard() {
        apply("", highlight: false)
        displayed = ""
        highlighted = false
    }

    public static func keepAndUnhighlight() {
        guard !displayed.isEmpty else { return }
        if highlighted {
            Typist.moveRight()
            highlighted = false
        }
        DictationSpacing.markCommitted(displayed)
        displayed = ""
    }

    private static func apply(_ text: String, highlight: Bool) {
        if displayed == text {
            if highlighted && !highlight {
                Typist.moveRight()
                highlighted = false
            }
            return
        }
        if displayed.isEmpty {
            Typist.typeText(text)
        } else if folds(text).hasPrefix(folds(displayed)) {
            if highlighted {
                Typist.moveRight()
                highlighted = false
            }
            Typist.typeText(String(text.dropFirst(displayed.count)))
        } else {
            if highlighted {
                Typist.moveRight()
                highlighted = false
            }
            Typist.deleteBackward(times: displayed.count)
            Typist.typeText(text)
        }
        displayed = text
        if highlight, !text.isEmpty {
            Typist.selectLeftWords(wordCount(text))
            highlighted = true
        } else {
            highlighted = false
        }
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func folds(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
    }
}
