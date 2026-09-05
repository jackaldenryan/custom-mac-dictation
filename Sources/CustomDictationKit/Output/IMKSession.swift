import Foundation
import InputMethodKit

public enum DictationInputServer {
    nonisolated(unsafe) private static var server: IMKServer?

    public static func start() {
        _ = InputSourceSetup.installBundle()
        guard server == nil else { return }
        let name = (Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String)
            ?? "CustomDictation_Connection"
        let bundle = Bundle.main.bundleIdentifier ?? "com.jackaldenryan.custom-mac-dictation"
        server = IMKServer(name: name, bundleIdentifier: bundle)
        DiagnosticLog.line("IMK server \(name)")
    }
}

@objc(DictationInputController)
public final class DictationInputController: IMKInputController {
    nonisolated(unsafe) static weak var current: DictationInputController?

    static var activeClient: (IMKTextInput & NSObjectProtocol)? {
        current?.client()
    }

    public override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        Self.current = self
        DiagnosticLog.line("IMK client activated")
    }

    public override func deactivateServer(_ sender: Any!) {
        if Self.current === self {
            Self.current = nil
        }
        super.deactivateServer(sender)
        DiagnosticLog.line("IMK client deactivated")
    }

    public override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        false
    }
}

final class IMKSessionClient: TextInputClient {
    nonisolated(unsafe) static let shared = IMKSessionClient()

    var isAvailable: Bool {
        if FieldEditor.focusedLooksLikeStub() { return false }
        guard let client = DictationInputController.activeClient else { return false }
        return client.selectedRange().location != NSNotFound
    }

    func selectedRange() -> NSRange {
        DictationInputController.activeClient?.selectedRange() ?? NSRange(location: NSNotFound, length: 0)
    }

    func selectedString() -> String? {
        guard isAvailable, let client = DictationInputController.activeClient else { return nil }
        let range = client.selectedRange()
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return client.attributedSubstring(from: range)?.string
    }

    func setMarkedText(_ string: String) {
        guard isAvailable, let client = DictationInputController.activeClient else { return }
        let end = (string as NSString).length
        client.setMarkedText(
            string,
            selectionRange: NSRange(location: 0, length: end),
            replacementRange: NSRange(location: NSNotFound, length: NSNotFound)
        )
    }

    func insertText(_ string: String) {
        guard isAvailable, let client = DictationInputController.activeClient else { return }
        client.insertText(string, replacementRange: NSRange(location: NSNotFound, length: NSNotFound))
    }

    func unmarkText() {
        guard isAvailable, let client = DictationInputController.activeClient else { return }
        let marked = client.markedRange()
        guard marked.location != NSNotFound else { return }
        let kept = client.attributedSubstring(from: marked)?.string ?? ""
        client.insertText(kept, replacementRange: marked)
    }

    func caretSnapshot() -> CaretSnapshot? {
        guard isAvailable, let client = DictationInputController.activeClient else { return nil }
        let sel = client.selectedRange()
        guard sel.location != NSNotFound else { return nil }
        let total = client.length()
        let beforeStart = max(0, sel.location - 32)
        let afterEnd = min(total, sel.location + sel.length + 32)
        let window = NSRange(location: beforeStart, length: max(0, afterEnd - beforeStart))
        let piece = client.attributedSubstring(from: window)?.string ?? ""
        return InsertionContext.snapshot(
            in: piece,
            utf16Location: sel.location - beforeStart,
            utf16Length: sel.length
        )
    }
}
