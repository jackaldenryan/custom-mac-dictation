import CoreGraphics
import Foundation

public struct KeyPressCommand: Equatable, Sendable {
    public var keyCode: UInt16
    public var flags: CGEventFlags
    public var character: String?

    public init(keyCode: UInt16, flags: CGEventFlags, character: String? = nil) {
        self.keyCode = keyCode
        self.flags = flags
        self.character = character
    }
}

public enum KeyPressGrammar {
    public static func parse(_ normalized: String) -> KeyPressCommand? {
        var tokens = normalized.split(separator: " ").map(String.init)
        guard tokens.first == "press" else { return nil }
        tokens.removeFirst()
        tokens.removeAll { $0 == "and" || $0 == "then" || $0 == "the" || $0 == "key" }

        var flags: CGEventFlags = []
        var leftover: [String] = []
        for token in tokens {
            if let modifier = modifierFlag(token) {
                flags.insert(modifier)
            } else {
                leftover.append(token)
            }
        }

        guard !leftover.isEmpty else { return nil }
        let joined = leftover.joined(separator: " ")
        if let character = punctuationCharacter(joined) {
            return KeyPressCommand(keyCode: 0, flags: flags, character: character)
        }

        guard leftover.count == 1, let keyToken = leftover.first else { return nil }

        if let named = namedKey(keyToken) {
            return KeyPressCommand(keyCode: named, flags: flags)
        }
        if let digit = digitKey(keyToken) {
            return KeyPressCommand(keyCode: digit, flags: flags)
        }
        if keyToken.count == 1, let scalar = keyToken.unicodeScalars.first, CharacterSet.letters.contains(scalar) {
            let letter = keyToken.lowercased()
            guard let code = letterKeyCodes[letter] else { return nil }
            return KeyPressCommand(keyCode: code, flags: flags)
        }
        if keyToken.count > 1, keyToken.hasPrefix("f"), let number = Int(keyToken.dropFirst()), (1...20).contains(number) {
            return KeyPressCommand(keyCode: functionKeyCodes[number]!, flags: flags)
        }
        return nil
    }

    private static func modifierFlag(_ token: String) -> CGEventFlags? {
        switch token {
        case "command", "cmd": return .maskCommand
        case "shift": return .maskShift
        case "option", "alt": return .maskAlternate
        case "control", "ctrl": return .maskControl
        case "function", "fn": return .maskSecondaryFn
        default: return nil
        }
    }

    private static func punctuationCharacter(_ name: String) -> String? {
        punctuationNames[name]
    }

    private static let punctuationNames: [String: String] = {
        var map: [String: String] = [:]
        let pairs: [(String, String)] = [
            ("comma", ","),
            ("period", "."), ("full stop", "."), ("dot", "."),
            ("question mark", "?"),
            ("exclamation mark", "!"), ("exclamation point", "!"),
            ("colon", ":"),
            ("semicolon", ";"),
            ("dash", "-"), ("hyphen", "-"), ("minus", "-"), ("minus sign", "-"),
            ("ellipsis", "…"), ("dot dot dot", "…"),
            ("quote", "\""), ("quotation mark", "\""), ("double quote", "\""),
            ("open quote", "\""), ("close quote", "\""), ("quotes", "\""),
            ("single quote", "'"), ("apostrophe", "'"),
            ("open parenthesis", "("), ("left parenthesis", "("),
            ("open parentheses", "("), ("left parentheses", "("),
            ("open paren", "("), ("left paren", "("),
            ("open parens", "("), ("left parens", "("),
            ("parentheses", "("), ("parenthesis", "("),
            ("close parenthesis", ")"), ("right parenthesis", ")"),
            ("close parentheses", ")"), ("right parentheses", ")"),
            ("close paren", ")"), ("right paren", ")"),
            ("close parens", ")"), ("right parens", ")"),
            ("open bracket", "["), ("left bracket", "["),
            ("open square bracket", "["), ("left square bracket", "["),
            ("close bracket", "]"), ("right bracket", "]"),
            ("close square bracket", "]"), ("right square bracket", "]"),
            ("open brace", "{"), ("left brace", "{"),
            ("open curly brace", "{"), ("left curly brace", "{"),
            ("close brace", "}"), ("right brace", "}"),
            ("close curly brace", "}"), ("right curly brace", "}"),
            ("slash", "/"), ("forward slash", "/"),
            ("backslash", "\\"),
            ("underscore", "_"),
            ("asterisk", "*"), ("star", "*"), ("star sign", "*"),
            ("plus", "+"), ("plus sign", "+"),
            ("equals", "="), ("equal sign", "="), ("equals sign", "="),
            ("ampersand", "&"), ("and sign", "&"),
            ("percent", "%"), ("percent sign", "%"),
            ("dollar", "$"), ("dollar sign", "$"),
            ("hash", "#"), ("pound", "#"), ("pound sign", "#"),
            ("number sign", "#"), ("hashtag", "#"),
            ("at sign", "@"), ("at symbol", "@"),
            ("tilde", "~"),
            ("backtick", "`"), ("grave", "`"), ("grave accent", "`"),
            ("caret", "^"), ("circumflex", "^"),
            ("pipe", "|"), ("vertical bar", "|"), ("bar", "|"),
            ("less than", "<"), ("left angle bracket", "<"),
            ("greater than", ">"), ("right angle bracket", ">")
        ]
        for (name, character) in pairs {
            map[name] = character
        }
        return map
    }()

    private static func namedKey(_ token: String) -> UInt16? {
        switch token {
        case "return", "enter": return 36
        case "tab": return 48
        case "escape", "esc": return 53
        case "space", "spacebar": return 49
        case "delete", "backspace": return 51
        case "forwarddelete": return 117
        case "up", "uparrow": return 126
        case "down", "downarrow": return 125
        case "left", "leftarrow": return 123
        case "right", "rightarrow": return 124
        case "home": return 115
        case "end": return 119
        case "pageup": return 116
        case "pagedown": return 121
        default: return nil
        }
    }

    private static func digitKey(_ token: String) -> UInt16? {
        let mapped: [String: UInt16] = [
            "0": 29, "zero": 29,
            "1": 18, "one": 18,
            "2": 19, "two": 19,
            "3": 20, "three": 20,
            "4": 21, "four": 21,
            "5": 23, "five": 23,
            "6": 22, "six": 22,
            "7": 26, "seven": 26,
            "8": 28, "eight": 28,
            "9": 25, "nine": 25
        ]
        return mapped[token]
    }

    private static let letterKeyCodes: [String: UInt16] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34,
        "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12,
        "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6
    ]

    private static let functionKeyCodes: [Int: UInt16] = [
        1: 122, 2: 120, 3: 99, 4: 118, 5: 96, 6: 97, 7: 98, 8: 100, 9: 101, 10: 109,
        11: 103, 12: 111, 13: 105, 14: 107, 15: 113, 16: 106, 17: 64, 18: 79, 19: 80, 20: 90
    ]
}
