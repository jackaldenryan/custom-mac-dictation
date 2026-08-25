import CoreGraphics
import Foundation

public struct KeyPressCommand: Equatable, Sendable {
    public var keyCode: UInt16
    public var flags: CGEventFlags
    public var character: String?
    public var times: Int

    public init(keyCode: UInt16, flags: CGEventFlags, character: String? = nil, times: Int = 1) {
        self.keyCode = keyCode
        self.flags = flags
        self.character = character
        self.times = times
    }
}

public enum KeyPressGrammar {
    public static func parse(_ spoken: String) -> KeyPressCommand? {
        let normalized = TranscriptNormalizer.normalize(spellOutPunctuation(spoken))
        var tokens = normalized.split(separator: " ").map(String.init)
        guard tokens.first == "press" else { return nil }
        tokens.removeFirst()
        tokens.removeAll { glueWords.contains($0) }

        var flags: CGEventFlags = []
        var leftover: [String] = []
        for token in tokens {
            if let modifier = modifierFlag(token) {
                flags.insert(modifier)
            } else {
                leftover.append(token)
            }
        }

        let times = popRepeatCount(&leftover)
        guard !leftover.isEmpty else { return nil }
        let joined = leftover.joined(separator: " ")
        if let spec = namedSpec(joined) {
            return KeyPressCommand(keyCode: spec.code, flags: flags.union(spec.flags), character: spec.character, times: times)
        }
        guard leftover.count == 1, let keyToken = leftover.first else { return nil }
        if let named = namedSpec(keyToken) {
            return KeyPressCommand(keyCode: named.code, flags: flags.union(named.flags), character: named.character, times: times)
        }
        if let digit = digitKey(keyToken) {
            return KeyPressCommand(keyCode: digit, flags: flags, times: times)
        }
        if keyToken.count == 1, let scalar = keyToken.unicodeScalars.first, CharacterSet.letters.contains(scalar) {
            guard let code = letterKeyCodes[keyToken] else { return nil }
            return KeyPressCommand(keyCode: code, flags: flags, times: times)
        }
        if keyToken.hasPrefix("f"), let number = Int(keyToken.dropFirst()), (1...20).contains(number) {
            return KeyPressCommand(keyCode: functionKeyCodes[number]!, flags: flags, times: times)
        }
        return nil
    }

    private static let glueWords: Set<String> = [
        "and", "then", "the", "key", "keys", "button"
    ]

    private static func modifierFlag(_ token: String) -> CGEventFlags? {
        switch token {
        case "command", "cmd": return .maskCommand
        case "shift": return .maskShift
        case "option", "alt", "alternate": return .maskAlternate
        case "control", "ctrl": return .maskControl
        case "function", "fn": return .maskSecondaryFn
        default: return nil
        }
    }

    private struct Spec {
        var code: UInt16
        var flags: CGEventFlags = []
        var character: String? = nil
    }

    private static func namedSpec(_ name: String) -> Spec? {
        specs[name]
    }

    private static func popRepeatCount(_ leftover: inout [String]) -> Int {
        guard let last = leftover.last else { return 1 }
        if last == "twice" {
            leftover.removeLast()
            return 2
        }
        if last == "thrice" {
            leftover.removeLast()
            return 3
        }
        guard last == "times" || last == "time" else { return 1 }
        leftover.removeLast()
        if leftover.count >= 2,
           let n = parseCount(leftover[leftover.count - 2] + " " + leftover[leftover.count - 1]) {
            leftover.removeLast(2)
            return clampCount(n)
        }
        if let token = leftover.last, let n = parseCount(token) {
            leftover.removeLast()
            return clampCount(n)
        }
        return 1
    }

    private static func clampCount(_ n: Int) -> Int {
        min(75, max(1, n))
    }

    private static func parseCount(_ token: String) -> Int? {
        if let n = Int(token) { return n }
        return countWords[token]
    }

    private static let countWords: [String: Int] = {
        var map: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
            "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
            "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70
        ]
        let tens: [(String, Int)] = [
            ("twenty", 20), ("thirty", 30), ("forty", 40), ("fifty", 50),
            ("sixty", 60), ("seventy", 70)
        ]
        let ones: [(String, Int)] = [
            ("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5),
            ("six", 6), ("seven", 7), ("eight", 8), ("nine", 9)
        ]
        for (tenName, tenVal) in tens {
            for (oneName, oneVal) in ones {
                map["\(tenName) \(oneName)"] = tenVal + oneVal
            }
        }
        return map
    }()

    private static func spellOutPunctuation(_ text: String) -> String {
        var pieces: [String] = []
        for scalar in text.unicodeScalars {
            if let name = punctuationSpokenNames[String(scalar)] {
                pieces.append(" ")
                pieces.append(name)
                pieces.append(" ")
            } else {
                pieces.append(String(scalar))
            }
        }
        return pieces.joined()
    }

    private static let punctuationSpokenNames: [String: String] = [
        "?": "question mark",
        "!": "exclamation mark",
        ":": "colon",
        ";": "semicolon",
        "-": "minus",
        "_": "underscore",
        "…": "ellipsis",
        "\"": "quote",
        "'": "apostrophe",
        "‘": "apostrophe",
        "’": "apostrophe",
        "(": "open parenthesis",
        ")": "close parenthesis",
        "[": "open square bracket",
        "]": "close square bracket",
        "{": "open brace",
        "}": "close brace",
        "/": "slash",
        "\\": "backslash",
        "*": "asterisk",
        "+": "plus",
        "=": "equals",
        "&": "ampersand",
        "%": "percent",
        "$": "dollar",
        "#": "hash",
        "@": "at sign",
        "~": "tilde",
        "˜": "tilde",
        "～": "tilde",
        "`": "backtick",
        "´": "backtick",
        "^": "caret",
        "ˆ": "caret",
        "|": "pipe",
        "¦": "pipe",
        "<": "open angle bracket",
        ">": "close angle bracket"
    ]

    private static let specs: [String: Spec] = {
        var map: [String: Spec] = [:]
        func add(_ names: [String], _ spec: Spec) {
            for name in names { map[name] = spec }
        }

        add(["return", "enter"], Spec(code: 36))
        add(["tab"], Spec(code: 48))
        add(["escape", "esc"], Spec(code: 53))
        add(["space", "spacebar"], Spec(code: 49))
        add(["delete", "backspace"], Spec(code: 51))
        add(["forward delete", "forwarddelete"], Spec(code: 117))
        add(["up", "up arrow", "uparrow"], Spec(code: 126))
        add(["down", "down arrow", "downarrow"], Spec(code: 125))
        add(["left", "left arrow", "leftarrow"], Spec(code: 123))
        add(["right", "right arrow", "rightarrow"], Spec(code: 124))
        add(["home"], Spec(code: 115))
        add(["end"], Spec(code: 119))
        add(["page up", "pageup"], Spec(code: 116))
        add(["page down", "pagedown"], Spec(code: 121))
        add(["caps lock", "capslock"], Spec(code: 57))

        add(["comma"], Spec(code: 43))
        add(["period", "full stop", "dot"], Spec(code: 47))
        add(["slash", "forward slash"], Spec(code: 44))
        add(["backslash"], Spec(code: 42))
        add(["minus", "minus sign", "dash", "hyphen"], Spec(code: 27))
        add(["equals", "equal", "equal sign", "equals sign"], Spec(code: 24))
        add(["grave", "grave accent", "backtick", "back tick", "back quote", "backquote"], Spec(code: 50))
        add(["semicolon"], Spec(code: 41))
        add(["apostrophe", "single quote"], Spec(code: 39))

        add(["open square bracket", "left square bracket", "open bracket", "left bracket", "square bracket"], Spec(code: 33))
        add(["close square bracket", "right square bracket", "close bracket", "right bracket"], Spec(code: 30))

        add(["question mark", "question"], Spec(code: 44, flags: .maskShift))
        add(["exclamation mark", "exclamation point", "exclamation"], Spec(code: 18, flags: .maskShift))
        add(["colon"], Spec(code: 41, flags: .maskShift))
        add(["underscore"], Spec(code: 27, flags: .maskShift))
        add(["quote", "quotation mark", "double quote", "open quote", "close quote", "quotes"], Spec(code: 39, flags: .maskShift))
        add(["open parenthesis", "left parenthesis", "open parentheses", "left parentheses", "open paren", "left paren", "open parens", "left parens", "parentheses", "parenthesis"], Spec(code: 25, flags: .maskShift))
        add(["close parenthesis", "right parenthesis", "close parentheses", "right parentheses", "close paren", "right paren", "close parens", "right parens"], Spec(code: 29, flags: .maskShift))
        add(["open brace", "left brace", "open curly brace", "left curly brace", "curly brace"], Spec(code: 33, flags: .maskShift))
        add(["close brace", "right brace", "close curly brace", "right curly brace"], Spec(code: 30, flags: .maskShift))
        add(["asterisk", "star", "star sign"], Spec(code: 28, flags: .maskShift))
        add(["plus", "plus sign"], Spec(code: 24, flags: .maskShift))
        add(["ampersand", "and sign"], Spec(code: 26, flags: .maskShift))
        add(["percent", "percent sign"], Spec(code: 23, flags: .maskShift))
        add(["dollar", "dollar sign"], Spec(code: 21, flags: .maskShift))
        add(["hash", "pound", "pound sign", "number sign", "hashtag"], Spec(code: 20, flags: .maskShift))
        add(["at sign", "at symbol", "at"], Spec(code: 19, flags: .maskShift))
        add(["tilde", "tilda", "squiggle", "wave"], Spec(code: 50, flags: .maskShift))
        add(["caret", "carat", "carrot", "circumflex", "hat"], Spec(code: 22, flags: .maskShift))
        add(["pipe", "vertical bar", "vertical line", "bar"], Spec(code: 42, flags: .maskShift))
        add(["open angle bracket", "left angle bracket", "angle bracket", "less than"], Spec(code: 43, flags: .maskShift))
        add(["close angle bracket", "right angle bracket", "greater than"], Spec(code: 47, flags: .maskShift))

        add(["ellipsis", "dot dot dot"], Spec(code: 0, character: "…"))

        let numberNames = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        let numberCodes: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
        for i in 0...9 {
            add([
                "number \(numberNames[i])",
                "number \(i)",
                "numeral \(numberNames[i])",
                "digit \(numberNames[i])",
                "digit \(i)"
            ], Spec(code: numberCodes[i]))
        }
        return map
    }()

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
