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
        for candidate in candidates(from: normalized) {
            for entry in table {
                if entry.names.contains(candidate) {
                    return decision(for: entry, modes: modes)
                }
            }
            if let entry = semanticEntry(candidate) {
                return decision(for: entry, modes: modes)
            }
        }
        return nil
    }

    public static func looksLikePunctuation(_ normalized: String) -> Bool {
        match(normalized: normalized, modes: [:]) != nil
    }

    public static func matchRawCharacter(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1 else { return nil }
        return table.contains(where: { $0.character == trimmed }) ? trimmed : nil
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

    private static func decision(
        for entry: (names: [String], character: String),
        modes: [String: PunctuationMode]
    ) -> PunctuationDecision? {
        let mode = modes[entry.names[0]] ?? .character
        switch mode {
        case .character: return .typeCharacter(entry.character)
        case .word: return .typeWord(entry.names[0])
        case .off: return nil
        }
    }

    private static func candidates(from normalized: String) -> [String] {
        var seen = Set<String>()
        var list: [String] = []
        func add(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            list.append(trimmed)
        }

        add(normalized)
        add(stripArticles(normalized))
        add(collapseRepeats(normalized))
        add(collapseRepeats(stripArticles(normalized)))
        add(unglue(normalized))
        add(stripArticles(unglue(normalized)))
        add(collapseRepeats(stripArticles(unglue(normalized))))
        return list
    }

    private static func stripArticles(_ text: String) -> String {
        let parts = text.split(separator: " ")
        var kept: [String] = []
        for part in parts {
            if part == "the" || part == "a" || part == "an" { continue }
            kept.append(String(part))
        }
        return kept.joined(separator: " ")
    }

    private static func collapseRepeats(_ text: String) -> String {
        var last = ""
        var tokens: [String] = []
        for token in text.split(separator: " ").map(String.init) {
            if token != last {
                tokens.append(token)
                last = token
            }
        }
        return tokens.joined(separator: " ")
    }

    private static func unglue(_ text: String) -> String {
        let prefixes = ["opening", "closing", "closed", "open", "close", "left", "right"]
        for prefix in prefixes where text.hasPrefix(prefix) && text.count > prefix.count {
            let index = text.index(text.startIndex, offsetBy: prefix.count)
            if text[index] != " " {
                return prefix + " " + text[index...]
            }
        }
        return text
    }

    private static func semanticEntry(_ text: String) -> (names: [String], character: String)? {
        var tokens = text.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }

        var side: Side = .open
        switch tokens[0] {
        case "open", "left", "opening":
            side = .open
            tokens.removeFirst()
        case "close", "right", "closing", "closed":
            side = .close
            tokens.removeFirst()
        default:
            break
        }
        guard !tokens.isEmpty else { return nil }
        let noun = tokens.joined(separator: " ")
        switch noun {
        case "parenthesis", "parentheses", "paren", "parens":
            return side == .close ? named(")", "close parenthesis") : named("(", "open parenthesis")
        case "bracket", "brackets", "square", "square bracket", "square brackets":
            return side == .close ? named("]", "close bracket") : named("[", "open bracket")
        case "brace", "braces", "curly", "curly brace", "curly braces", "curly bracket", "curly brackets":
            return side == .close ? named("}", "close brace") : named("{", "open brace")
        case "quote", "quotes", "quotation", "quotation mark", "double quote":
            return named("\"", "quote")
        default:
            return nil
        }
    }

    private static func named(_ character: String, _ key: String) -> (names: [String], character: String) {
        ([key], character)
    }

    private enum Side {
        case open
        case close
    }
}

public enum PunctuationDecision: Equatable, Sendable {
    case typeCharacter(String)
    case typeWord(String)
}
