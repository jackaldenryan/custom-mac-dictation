import Foundation

/// Apple's final result is usually better than the live one and is trusted,
/// including when it drops words. One failure is not a better guess: the
/// final loses the start of the phrase's audio and transcribes the clipped
/// tail of the first word as a stray letter. "Later I will go outside"
/// became "r I will go outside" (Oct 7), and the logs show "Thanks, are
/// they" -> "X, are they", "they have merged" -> "K have merged", "key
/// account review" -> "P account review".
///
/// Rule: when the final starts with a lone letter (not "a" / "I") where the
/// live text had a whole word, and the rest of the final matches the rest
/// of the live text, keep the live opening up to that word.
public enum FinalReconcile {
    public static func restoreClippedStart(live: String, final: String) -> String {
        let liveTokens = live.split(whereSeparator: \.isWhitespace).map(String.init)
        let finalTokens = final.split(whereSeparator: \.isWhitespace).map(String.init)
        let liveWords = liveTokens.map(normalize)
        let finalWords = finalTokens.map(normalize)
        guard let first = finalWords.first, finalWords.count <= liveWords.count else { return final }
        guard first.count == 1, first.allSatisfy(\.isLetter), first != "a", first != "i" else { return final }
        let clipped = liveWords.count - finalWords.count
        guard liveWords[clipped].count > 1,
              Array(liveWords[(clipped + 1)...]) == Array(finalWords.dropFirst())
        else { return final }
        return (liveTokens[...clipped] + finalTokens.dropFirst()).joined(separator: " ")
    }

    /// Lowercased letters, digits and apostrophes ("Jack." == "jack").
    static func normalize(_ token: String) -> String {
        String(token.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" })
    }
}
