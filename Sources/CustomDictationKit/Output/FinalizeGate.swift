import Foundation

public struct FinalizeGate: Equatable, Sendable {
    public var pending = false
    public var lastVolatileAt = Date.distantPast

    public init() {}

    public mutating func notePartial(at: Date = Date()) {
        pending = true
        lastVolatileAt = at
    }

    public mutating func noteFinal() {
        pending = false
    }

    public func shouldForceFinalize(delay: Double, now: Date = Date()) -> Bool {
        pending && now.timeIntervalSince(lastVolatileAt) >= delay
    }
}

public enum LiveInsertPath: String, Equatable, Sendable {
    case ax
    case hid
    case skipped
}

public enum LiveCommitPolicy {
    public static func shouldFinishAXMark(_ path: LiveInsertPath) -> Bool {
        path == .ax
    }
}
