import Foundation

public struct PunctuationMatch: Equatable, Sendable {
    public var character: String
    public var word: String
}

public enum PunctuationPolicy {
    public static let table: [(names: [String], character: String)] = [
        (["comma"], ","),
        (["period", "full stop", "dot"], "."),
        (["question mark"], "?"),
        (["exclamation mark", "exclamation point"], "!"),
        (["colon"], ":"),
        (["semicolon"], ";"),
        (["dash", "hyphen"], "-"),
        (["ellipsis", "dot dot dot"], "…"),
        (["quote", "quotation mark", "double quote"], "\""),
        (["single quote", "apostrophe"], "'"),
        (["open parenthesis", "left parenthesis"], "("),
        (["close parenthesis", "right parenthesis"], ")"),
        (["open bracket", "left bracket"], "["),
        (["close bracket", "right bracket"], "]"),
        (["open brace", "left brace"], "{"),
        (["close brace", "right brace"], "}"),
        (["slash", "forward slash"], "/"),
        (["backslash"], "\\"),
        (["underscore"], "_")
    ]

    public static func match(normalized: String, modes: [String: PunctuationMode]) -> PunctuationDecision? {
        if let forced = literalWord(normalized) {
            return .typeWord(forced)
        }
        for entry in table {
            if entry.names.contains(normalized) {
                let mode = modes[entry.names[0]] ?? .character
                switch mode {
                case .character: return .typeCharacter(entry.character)
                case .word: return .typeWord(entry.names[0])
                case .off: return nil
                }
            }
        }
        return nil
    }

    public static func literalWord(_ normalized: String) -> String? {
        let prefix = "the word "
        guard normalized.hasPrefix(prefix) else { return nil }
        let rest = String(normalized.dropFirst(prefix.count))
        for entry in table where entry.names.contains(rest) {
            return rest
        }
        return rest.isEmpty ? nil : rest
    }
}

public enum PunctuationDecision: Equatable, Sendable {
    case typeCharacter(String)
    case typeWord(String)
}
