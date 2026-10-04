import Foundation

/// Insertion strategy under test.
///
/// Makes the choice of how dictated text gets on screen explicit, so each
/// strategy is driven through the same simulated fields and measured on the
/// same properties (live text before finalize, underline/mark, flicker,
/// caret correctness, coverage). An Input Method (IMK) strategy was tried
/// and removed in 0.1.40: macOS 26 does not list classic IMK apps, so it
/// could not be selected.
public enum InsertStrategy: String, CaseIterable, Sendable {
    /// What v0.1.39 shipped: incremental HID keystroke emulation everywhere.
    /// No AX write, no live selection. Kept as the baseline.
    case releaseHID
    /// Current: AX write in native fields (Notes), with the live phrase
    /// selected (Voice Control-like highlight); HID keystrokes in every web
    /// engine and wherever AX can't write. Finder / Notes sidebar skipped.
    case axHID
}

public struct InsertTradeoffs: Sendable {
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
        case .axHID: return "ax-hid (current)"
        }
    }

    public var tradeoffs: InsertTradeoffs {
        switch strategy {
        case .releaseHID:
            return InsertTradeoffs(
                coverage: "types everywhere, including Finder (bad: should skip) and Cursor stub (old code typed into stub)",
                underline: "none anywhere: partials are plain keystrokes, no mark/selection"
            )
        case .axHID:
            return InsertTradeoffs(
                coverage: "AX only in native fields (Notes); HID in every web engine (Slack, Cursor, OpenCode, browsers) with no AX attempt; Finder and Notes sidebar skipped",
                underline: "selection highlight only in native AX fields (Notes); plain text elsewhere"
            )
        }
    }

    /// Drive one shaped update into a simulated field the way each strategy
    /// would in production. `keepSelected == true` models a live partial;
    /// `false` models the committed final.
    public func apply(shaped: String, keepSelected: Bool, to field: SimulatedField) {
        switch strategy {
        case .releaseHID:
            field.apply(shaped: shaped, keepSelected: keepSelected, forceHID: true)
        case .axHID:
            field.apply(shaped: shaped, keepSelected: keepSelected)
        }
    }
}
