import Foundation

/// Apple's SpeechAnalyzer sends a sentence's closing punctuation twice:
/// first as a lone final ("?") right after the words' final, and again at
/// the START of the next segment ("? I don't know it seems OK"). Typing both
/// gave "What do you think?? I don't know", "Let's test.. OK", and when the
/// next segment went to a different, empty field, a message that began with
/// "." (Oct 3 Slack and Claude logs).
///
/// Rule: punctuation that arrives at the start of a segment, or alone, is
/// typed only when it can attach to a word we just typed in this app and the
/// caret (when AX can read it) also sits right after such a word. Otherwise
/// it is a duplicate or has nothing to close, and is dropped.
public enum BoundaryPunctuation {
    static let marks: Set<Character> = [".", "?", "!", ",", ";", ":", "…"]
    static let terminal: Set<Character> = [".", "?", "!", "…"]

    /// The leading punctuation run (with its trailing spaces) and the rest.
    public static func splitLeading(_ text: String) -> (lead: String, rest: String) {
        let trimmed = text.drop { $0.isWhitespace }
        let lead = trimmed.prefix { marks.contains($0) }
        guard !lead.isEmpty else { return ("", text) }
        let rest = trimmed.dropFirst(lead.count).drop { $0.isWhitespace }
        return (String(lead), String(rest))
    }

    /// Text a punctuation mark can close: a word, number, or closing
    /// bracket/quote. Not another punctuation mark, not nothing.
    public static func attachable(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ")]}\"'”’".contains(ch)
    }

    public static func isTerminal(_ ch: Character?) -> Bool {
        guard let ch else { return false }
        return terminal.contains(ch)
    }

    /// - tail: last character dictation typed, if it was typed in the app
    ///   that is frontmost now (nil after a command or an app switch).
    /// - snapshot: AX view of the caret, when the field exposes one. Web
    ///   fields can report it one keystroke late, so `tail` may veto it.
    public static func canAttach(tail: Character?, snapshot: CaretSnapshot?) -> Bool {
        if let tail, !attachable(tail) { return false }
        if let snap = snapshot {
            if snap.atStart || snap.selectedLength > 0 { return false }
            if let before = snap.before, before.isNewline { return false }
            guard let ch = snap.lastNonSpaceBefore else { return false }
            return attachable(ch)
        }
        guard let tail else { return false }
        return attachable(tail)
    }

    /// Text to post-process, or nil when nothing is left to type.
    public static func clean(_ text: String, canAttach: Bool) -> String? {
        let (lead, rest) = splitLeading(text)
        if lead.isEmpty || canAttach { return text }
        return rest.isEmpty ? nil : rest
    }
}
