import Foundation

public enum LivePhrase {
    nonisolated(unsafe) public static var displayed = ""

    public static func show(_ text: String) {
        apply(text, keepSelected: !text.isEmpty)
    }

    public static func commit(_ text: String) {
        apply(text, keepSelected: false)
        displayed = ""
    }

    public static func discard() {
        apply("", keepSelected: false)
        displayed = ""
    }

    public static func keepAndUnhighlight() {
        guard !displayed.isEmpty else { return }
        Typist.moveRight()
        DictationSpacing.markCommitted(displayed)
        displayed = ""
    }

    private static func apply(_ text: String, keepSelected: Bool) {
        if displayed == text {
            if !keepSelected, !displayed.isEmpty {
                Typist.moveRight()
            }
            return
        }
        if displayed.isEmpty {
            Typist.typeText(text)
        } else if text.hasPrefix(displayed) {
            Typist.moveRight()
            Typist.typeText(String(text.dropFirst(displayed.count)))
        } else {
            Typist.deleteSelection()
            Typist.typeText(text)
        }
        displayed = text
        if keepSelected, !text.isEmpty {
            Typist.selectLeft(characters: text.count)
        }
    }
}
