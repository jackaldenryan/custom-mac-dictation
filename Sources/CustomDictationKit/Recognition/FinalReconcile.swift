import Foundation

/// Apple's final result sometimes loses the start of a phrase that its live
/// result already showed: "but not the rainbow pride flag" became "the
/// rainbow pride flag", "doesn't mean" became "mean", and a clipped first
/// word can survive as a fragment ("Later I will go outside" became
/// "r I will go outside"). The app trusted the final and retyped the
/// phrase from it, so words you saw on screen vanished (~1-2% of phrases in
/// the logs, Aug-Oct).
///
/// Rule: when the final is exactly the live text with its opening cut off,
/// keep the live opening. Apple's real false-start cleanups ("fast faster" ->
/// "faster", "that that's" -> "that's") are left alone, as is any final
/// that changes the words rather than only cutting the start.
public enum FinalReconcile {
    public static func restoreDroppedStart(live: String, final: String) -> String {
        let liveTokens = live.split(whereSeparator: \.isWhitespace).map(String.init)
        let finalTokens = final.split(whereSeparator: \.isWhitespace).map(String.init)
        let liveWords = liveTokens.map(normalize)
        let finalWords = finalTokens.map(normalize)
        guard !finalWords.isEmpty, !finalWords.contains(""), finalWords.count <= liveWords.count else {
            return final
        }
        let cut = liveWords.count - finalWords.count
        // Whole leading words dropped: the final is the live words' tail.
        if cut > 0, Array(liveWords[cut...]) == finalWords {
            let lastDropped = liveWords[cut - 1]
            // "fast faster", "that that's": a false start Apple cleaned up.
            // (One-letter words like "a" / "I" are real words, not stutters.)
            if lastDropped.count >= 2 || lastDropped == finalWords[0], finalWords[0].hasPrefix(lastDropped) { return final }
            return (liveTokens[..<cut] + finalTokens).joined(separator: " ")
        }
        // The first remaining word was clipped: "Later" -> "r".
        let fragment = finalWords[0]
        let whole = liveWords[cut]
        if Array(liveWords[(cut + 1)...]) == Array(finalWords.dropFirst()),
           whole.count > fragment.count, whole.hasSuffix(fragment) {
            return (liveTokens[...cut] + finalTokens.dropFirst()).joined(separator: " ")
        }
        return final
    }

    /// Lowercased letters, digits and apostrophes ("Jack." == "jack").
    static func normalize(_ token: String) -> String {
        String(token.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" })
    }
}
