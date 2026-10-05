import AppKit
import CoreGraphics
import Foundation

/// "delete that": delete whatever is selected in the front app.
///
/// - Text: the Delete key removes the selected text. If the field reports
///   an empty selection, nothing happens (Delete would eat the character
///   before the cursor, which is not what "delete that" means).
/// - Finder: selected files go to the Trash with Command-Delete (plain
///   Delete does nothing there). Renaming a file (a text field) is text.
/// - Anything else (mail lists, Slack messages, ...): the Delete key.
public enum DeleteSelection {
    public enum Key: Equatable, Sendable {
        case delete
        case commandDelete
        case nothing
    }

    /// - textSelectionLength: selection length of the focused text field,
    ///   or nil when the focus is not a text field AX can read (web fields,
    ///   lists). Unknown means send Delete.
    public static func key(bundleID: String?, textSelectionLength: Int?) -> Key {
        if let length = textSelectionLength {
            return length > 0 ? .delete : .nothing
        }
        if bundleID == "com.apple.finder" { return .commandDelete }
        return .delete
    }

    @discardableResult
    public static func run() -> Key {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let key = key(bundleID: bundleID, textSelectionLength: FieldEditor.focusedTextSelectionLength())
        switch key {
        case .delete:
            Typist.press(keyCode: 51, flags: [])
        case .commandDelete:
            Typist.press(keyCode: 51, flags: .maskCommand)
        case .nothing:
            DiagnosticLog.line("Delete that: nothing selected in the text field")
        }
        return key
    }
}
