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
        (["dash", "hyphen", "minus", "minus sign"], "-"),
        (["ellipsis", "dot dot dot"], "…"),
        (["quote", "quotation mark", "double quote", "open quote", "close quote", "quotes"], "\""),
        (["single quote", "apostrophe"], "'"),
        ([
            "open parenthesis", "left parenthesis",
            "open parentheses", "left parentheses",
            "open paren", "left paren",
            "open parens", "left parens",
            "parentheses", "parenthesis"
        ], "("),
        ([
            "close parenthesis", "right parenthesis",
            "close parentheses", "right parentheses",
            "close paren", "right paren",
            "close parens", "right parens"
        ], ")"),
        (["open bracket", "left bracket", "open square bracket", "left square bracket"], "["),
        (["close bracket", "right bracket", "close square bracket", "right square bracket"], "]"),
        (["open brace", "left brace", "open curly brace", "left curly brace"], "{"),
        (["close brace", "right brace", "close curly brace", "right curly brace"], "}"),
        (["slash", "forward slash"], "/"),
        (["backslash"], "\\"),
        (["underscore"], "_"),
        (["asterisk", "star", "star sign"], "*"),
        (["plus", "plus sign"], "+"),
        (["equals", "equal sign", "equals sign"], "="),
        (["ampersand", "and sign"], "&"),
        (["percent", "percent sign"], "%"),
        (["dollar", "dollar sign"], "$"),
        (["hash", "pound", "pound sign", "number sign", "hashtag"], "#"),
        (["at sign", "at symbol"], "@"),
        (["tilde"], "~"),
        (["backtick", "grave", "grave accent"], "`"),
        (["caret", "circumflex"], "^"),
        (["pipe", "vertical bar", "bar"], "|"),
        (["less than", "left angle bracket"], "<"),
        (["greater than", "right angle bracket"], ">")
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
