import CoreGraphics
import Foundation

public struct ClickCommand: Equatable, Sendable {
    public var flags: CGEventFlags
    public var right: Bool
    public var times: Int
}

public enum ClickGrammar {
    public static func parse(_ spoken: String) -> ClickCommand? {
        var tokens = TranscriptNormalizer.normalize(spoken).split(separator: " ").map(String.init)
        if tokens.first == "press" { tokens.removeFirst() }
        tokens.removeAll { $0 == "the" || $0 == "and" || $0 == "a" }
        guard tokens.contains("click") else { return nil }
        var flags: CGEventFlags = []
        var times = 1
        var right = false
        var leftover: [String] = []
        for token in tokens {
            switch token {
            case "command", "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option", "alt": flags.insert(.maskAlternate)
            case "control", "ctrl": flags.insert(.maskControl)
            case "double": times = 2
            case "triple": times = 3
            case "right": right = true
            case "left": right = false
            case "click": continue
            default: leftover.append(token)
            }
        }
        guard leftover.isEmpty else { return nil }
        if flags.isEmpty, times == 1, !right { return nil }
        return ClickCommand(flags: flags, right: right, times: times)
    }

    public static func shouldHold(_ normalized: String) -> Bool {
        if parse(normalized) != nil { return true }
        let tokens = normalized.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return false }
        if tokens.first == "press" { return tokens.count == 1 || shouldHold(tokens.dropFirst().joined(separator: " ")) }
        return tokens.allSatisfy(isClickToken)
    }

    private static func isClickToken(_ token: String) -> Bool {
        switch token {
        case "command", "cmd", "shift", "option", "alt", "control", "ctrl",
             "double", "triple", "right", "left", "click", "press":
            return true
        default:
            return false
        }
    }
}
