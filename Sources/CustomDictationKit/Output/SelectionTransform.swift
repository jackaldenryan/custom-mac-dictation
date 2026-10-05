import AppKit
import Foundation

public enum SelectionTransformError: Error {
    case nothingSelected
}

public enum SelectionTransform {
    public enum Kind {
        case capitalize
        case uppercase
        case lowercase
        /// "remove spaces": "my file name" -> "myfilename". Spaces and tabs
        /// go; line breaks stay.
        case removeSpaces
    }

    public static func apply(_ kind: Kind) throws {
        if let raw = FieldEditor.selectedString(), !raw.isEmpty {
            if FieldEditor.replaceSelection(transform(raw, kind: kind)) {
                return
            }
        }
        let pasteboard = NSPasteboard.general
        let previous = snapshot(pasteboard)
        let beforeChangeCount = pasteboard.changeCount

        _ = Typist.systemEventsKeystroke("c", command: true)
        var copied = waitForPasteboardChange(from: beforeChangeCount, pasteboard: pasteboard)
        if !copied {
            Typist.press(keyCode: 8, flags: .maskCommand, hidSystem: true)
            copied = waitForPasteboardChange(from: beforeChangeCount, pasteboard: pasteboard)
        }
        let raw = pasteboard.string(forType: .string)
        if !copied || raw == nil || raw?.isEmpty == true {
            restore(previous, onto: pasteboard)
            throw SelectionTransformError.nothingSelected
        }

        let transformed = transform(raw!, kind: kind)

        pasteboard.clearContents()
        pasteboard.setString(transformed, forType: .string)
        if !Typist.systemEventsKeystroke("v", command: true) {
            Typist.press(keyCode: 9, flags: .maskCommand, hidSystem: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            restore(previous, onto: pasteboard)
        }
    }

    public static func transform(_ raw: String, kind: Kind) -> String {
        switch kind {
        case .capitalize:
            return raw.localizedCapitalized
        case .uppercase:
            return raw.localizedUppercase
        case .lowercase:
            return raw.localizedLowercase
        case .removeSpaces:
            return String(raw.filter { !($0.isWhitespace && !$0.isNewline) })
        }
    }

    private static func waitForPasteboardChange(from changeCount: Int, pasteboard: NSPasteboard) -> Bool {
        let deadline = Date().addingTimeInterval(0.7)
        while Date() < deadline {
            if pasteboard.changeCount != changeCount { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return pasteboard.changeCount != changeCount
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [(NSPasteboard.PasteboardType, Data)] {
        (pasteboard.types ?? []).compactMap { type in
            guard let data = pasteboard.data(forType: type) else { return nil }
            return (type, data)
        }
    }

    private static func restore(_ items: [(NSPasteboard.PasteboardType, Data)], onto pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        for (type, data) in items {
            pasteboard.setData(data, forType: type)
        }
    }
}
