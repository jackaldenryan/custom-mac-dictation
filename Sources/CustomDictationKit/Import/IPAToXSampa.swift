import Foundation

public enum IPAToXSampa {
    public static func convert(_ ipa: String) -> String {
        var output = ""
        let scalars = Array(ipa.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let current = scalars[index]
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            if current == "t", next == "\u{0361}" || next == "͡" {
                if index + 2 < scalars.count, scalars[index + 2] == "ʃ" {
                    output += "tS"
                    index += 3
                    continue
                }
            }
            if current == "d", next == "\u{0361}" || next == "͡" {
                if index + 2 < scalars.count, scalars[index + 2] == "ʒ" {
                    output += "dZ"
                    index += 3
                    continue
                }
            }
            output += map[current] ?? String(current)
            index += 1
        }
        return output
    }

    public static func filter(_ xsampa: String, allowed: Set<String>) -> String? {
        guard !xsampa.isEmpty else { return nil }
        if allowed.isEmpty { return xsampa }
        let tokens = tokenize(xsampa)
        let kept = tokens.filter { allowed.contains($0) }
        if kept.isEmpty { return nil }
        return kept.joined()
    }

    private static func tokenize(_ xsampa: String) -> [String] {
        var tokens: [String] = []
        var index = xsampa.startIndex
        while index < xsampa.endIndex {
            let twoEnd = xsampa.index(index, offsetBy: 2, limitedBy: xsampa.endIndex) ?? xsampa.endIndex
            let two = String(xsampa[index..<twoEnd])
            if two.count == 2, multi.contains(two) {
                tokens.append(two)
                index = twoEnd
                continue
            }
            tokens.append(String(xsampa[index]))
            index = xsampa.index(after: index)
        }
        return tokens
    }

    private static let multi: Set<String> = ["tS", "dZ", "r\\"]

    private static let map: [Unicode.Scalar: String] = [
        "æ": "{",
        "ɑ": "A",
        "ɒ": "Q",
        "ɔ": "O",
        "ə": "@",
        "ɚ": "@`",
        "ɛ": "E",
        "ɝ": "3`",
        "ɜ": "3",
        "ɪ": "I",
        "ɨ": "1",
        "ʊ": "U",
        "ʌ": "V",
        "ɯ": "M",
        "ø": "2",
        "œ": "9",
        "ɶ": "&",
        "ɐ": "6",
        "ɵ": "8",
        "ʉ": "}",
        "ʏ": "Y",
        "ŋ": "N",
        "ɲ": "J",
        "ʃ": "S",
        "ʒ": "Z",
        "θ": "T",
        "ð": "D",
        "ɡ": "g",
        "ʁ": "R",
        "χ": "X",
        "ɣ": "G",
        "ħ": "X\\",
        "ʕ": "?\\",
        "ʔ": "?",
        "ɹ": "r\\",
        "ɻ": "r\\`",
        "ɾ": "4",
        "ɽ": "r`",
        "ɫ": "5",
        "ɬ": "K",
        "ɮ": "K\\",
        "ʋ": "P",
        "ɥ": "H",
        "ɰ": "M\\",
        "ç": "C",
        "ʝ": "j\\",
        "β": "B",
        "ɸ": "p\\",
        "ː": ":",
        "ˈ": "\"",
        "ˌ": "%",
        "̩": "=",
        "̃": "~",
        "\u{0361}": ""
    ]
}
