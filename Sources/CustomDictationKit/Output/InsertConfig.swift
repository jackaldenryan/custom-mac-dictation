import Foundation

/// Insertion strategy under test.
///
/// The app has tried three different ways to get dictated text on screen.
/// This type makes the choice explicit so every strategy can be driven
/// through the same simulated fields and measured on the same properties
/// (live text before finalize, underline/mark, flicker, caret correctness,
/// coverage) instead of comparing hand-written engine models.
public enum InsertStrategy: String, CaseIterable, Sendable {
    /// What the released app (`origin/main`, v0.1.39) actually does for
    /// dictation text: incremental HID keystroke emulation everywhere.
    /// No AX write, no marked text, no live selection.
    /// (Case transforms in the release are AX-only in Notes/Chrome URL and
    /// otherwise fail; that is modeled in CheckFieldScenarios, not here.)
    case releaseHID
    /// Local default (`useInputMethod == false`): AX write where the field
    /// profile allows it (native fields like Notes; never web engines), otherwise HID keystrokes.
    /// Live partials select the mark (Voice Control-like highlight) on the
    /// AX path; the HID path shows live text with no underline.
    case axHID
    /// Local IMK toggle on: `setMarkedText`/`insertText` where the field has
    /// a text client, otherwise skip (Finder, Notes sidebar, Cursor stub get
    /// nothing). True OS underline wherever it types.
    case imkOnly
    /// Hypothetical, not shipped: IMK where a client exists, otherwise fall
    /// back to the axHID behavior. Included so the matrix can show whether
    /// "IMK plus fallback" would rescue IMK's coverage gaps.
    case imkFallback
}

public struct InsertTradeoffs: Sendable {
    public var requiresAccessibilityPermission: Bool
    public var requiresInputSourceInstallAndSelect: Bool
    public var macOS26ClassicIMKListed: Bool
    public var stillNeedsAXForClicksAndKeys: Bool
    public var coverage: String
    public var underline: String
}

public struct InsertConfig: Sendable, Equatable {
    public var strategy: InsertStrategy

    public init(_ strategy: InsertStrategy) {
        self.strategy = strategy
    }

    public static var all: [InsertConfig] {
        InsertStrategy.allCases.map(InsertConfig.init)
    }

    public var id: String { strategy.rawValue }

    public var title: String {
        switch strategy {
        case .releaseHID: return "release-HID (shipped v0.1.39)"
        case .axHID: return "ax-hid (local default, IMK off)"
        case .imkOnly: return "imk-only (local toggle on)"
        case .imkFallback: return "imk-fallback (hypothetical)"
        }
    }

    public var tradeoffs: InsertTradeoffs {
        switch strategy {
        case .releaseHID:
            return InsertTradeoffs(
                requiresAccessibilityPermission: true,
                requiresInputSourceInstallAndSelect: false,
                macOS26ClassicIMKListed: true,
                stillNeedsAXForClicksAndKeys: true,
                coverage: "types everywhere, including Finder (bad: should skip) and Cursor stub (old code typed into stub)",
                underline: "none anywhere: partials are plain keystrokes, no mark/selection"
            )
        case .axHID:
            return InsertTradeoffs(
                requiresAccessibilityPermission: true,
                requiresInputSourceInstallAndSelect: false,
                macOS26ClassicIMKListed: true,
                stillNeedsAXForClicksAndKeys: true,
                coverage: "AX only in native fields (Notes); HID in every web engine (Slack, Cursor, OpenCode, browsers) with no AX attempt; Finder and Notes sidebar skipped",
                underline: "selection highlight only in native AX fields (Notes); plain text elsewhere"
            )
        case .imkOnly:
            return InsertTradeoffs(
                requiresAccessibilityPermission: true,
                requiresInputSourceInstallAndSelect: true,
                macOS26ClassicIMKListed: false,
                stillNeedsAXForClicksAndKeys: true,
                coverage: "every text client (Notes, Slack, Cursor, OpenCode, browsers, Zoom); skips Finder/sidebar/stub (good safety, but dictation does nothing there)",
                underline: "true OS marked-text underline everywhere it types"
            )
        case .imkFallback:
            return InsertTradeoffs(
                requiresAccessibilityPermission: true,
                requiresInputSourceInstallAndSelect: true,
                macOS26ClassicIMKListed: false,
                stillNeedsAXForClicksAndKeys: true,
                coverage: "IMK where client exists, else AX/HID with the same Finder/sidebar skip",
                underline: "OS underline where IMK; selection highlight where AX fallback; none on HID fallback"
            )
        }
    }

    /// Drive one shaped update into a simulated field the way each strategy
    /// would in production. `keepSelected == true` models a live partial
    /// (mark/underlined); `false` models the committed final.
    public func apply(shaped: String, keepSelected: Bool, to field: SimulatedField) {
        switch strategy {
        case .releaseHID:
            field.apply(shaped: shaped, keepSelected: keepSelected, useInputMethod: false, forceHID: true)
        case .axHID:
            field.apply(shaped: shaped, keepSelected: keepSelected, useInputMethod: false)
        case .imkOnly:
            field.apply(shaped: shaped, keepSelected: keepSelected, useInputMethod: true)
        case .imkFallback:
            if field.profile.hasClient {
                field.apply(shaped: shaped, keepSelected: keepSelected, useInputMethod: true)
            } else {
                field.apply(shaped: shaped, keepSelected: keepSelected, useInputMethod: false)
            }
        }
    }
}
