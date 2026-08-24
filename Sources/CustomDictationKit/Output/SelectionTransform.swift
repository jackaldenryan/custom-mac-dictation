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
    }

    public static func apply(_ kind: Kind) throws {
        let pasteboard = NSPasteboard.general
        let previous = snapshot(pasteboard)
        let beforeChangeCount = pasteboard.changeCount

        Typist.press(keyCode: 8, flags: .maskCommand)
        let copied = waitForPasteboardChange(from: beforeChangeCount, pasteboard: pasteboard)
        let raw = pasteboard.string(forType: .string)
        if !copied || raw == nil || raw?.isEmpty == true {
            restore(previous, onto: pasteboard)
            throw SelectionTransformError.nothingSelected
        }

        let transformed: String
        switch kind {
        case .capitalize:
            transformed = raw!.localizedCapitalized
        case .uppercase:
            transformed = raw!.localizedUppercase
        case .lowercase:
            transformed = raw!.localizedLowercase
        }

        pasteboard.clearContents()
        pasteboard.setString(transformed, forType: .string)
        Typist.press(keyCode: 9, flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            restore(previous, onto: pasteboard)
        }
    }

    private static func waitForPasteboardChange(from changeCount: Int, pasteboard: NSPasteboard) -> Bool {
        let deadline = Date().addingTimeInterval(0.35)
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
