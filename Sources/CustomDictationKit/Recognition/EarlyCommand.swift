import Foundation

/// Running commands from live text instead of Apple's final.
public enum EarlyCommand {
    /// How long a live transcript that is a whole command must stay
    /// unchanged before it runs. Short enough to feel instant, long enough
    /// that "press the down key" can still grow into "... five times".
    public static let settleSeconds = 0.4

    /// A command that already ran from live text.
    public struct Ran: Equatable, Sendable {
        public var normalized: String
        public var at: Date
        public init(normalized: String, at: Date) {
            self.normalized = normalized
            self.at = at
        }
    }

    public enum FinalAction: Equatable, Sendable {
        /// The final is the command that already ran: do nothing.
        case skip
        /// Route this text (the whole final, or what came after the command).
        case route(String)
    }

    /// What to do with Apple's final after a command may have run early.
    public static func resolveFinal(_ final: String, ran: Ran?, now: Date) -> FinalAction {
        guard let ran, now.timeIntervalSince(ran.at) < 10 else { return .route(final) }
        let words = final.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let normalized = TranscriptNormalizer.normalize(final)
        if normalized == ran.normalized || final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .skip }
        let commandWords = ran.normalized.split(separator: " ").count
        // Spoke on after the command: run only the new part.
        if normalized.hasPrefix(ran.normalized + " "), words.count > commandWords {
            return .route(words.dropFirst(commandWords).joined(separator: " "))
        }
        // Apple reworded the same short utterance ("capitalize that" ->
        // "capitalized that"): the command already ran, so never also type it.
        if normalized.split(separator: " ").count <= commandWords { return .skip }
        return .route(final)
    }
}
