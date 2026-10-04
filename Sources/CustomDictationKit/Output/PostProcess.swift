import Foundation

/// What the post-process needs to shape one transcript before typing.
public struct PostProcessInput: Equatable, Sendable {
    public var text: String
    public var pendingLeadSpace: Bool
    public var midSentence: Bool
    public var snapshot: CaretSnapshot?

    public init(
        text: String,
        pendingLeadSpace: Bool,
        midSentence: Bool,
        snapshot: CaretSnapshot?
    ) {
        self.text = text
        self.pendingLeadSpace = pendingLeadSpace
        self.midSentence = midSentence
        self.snapshot = snapshot
    }
}

/// The one built-in post-process: fit Apple's text to the caret.
/// Sentence start capitalizes; mid-sentence lowers Apple's segment-start
/// capital; a space is added only when the text before the caret needs one.
/// Runs on live text and on Apple's final alike. Commands are never shaped.
public enum DefaultPostProcess {
    public static func apply(_ input: PostProcessInput) -> String {
        let body = isMidSentence(input)
            ? SentenceFit.midSentence(input.text)
            : SentenceFit.sentenceStart(input.text)
        guard !body.isEmpty else { return body }
        if FieldFit.needsLeadSpace(body, snapshot: input.snapshot, pendingLeadSpace: input.pendingLeadSpace) {
            return " " + body
        }
        return body
    }

    static func isMidSentence(_ input: PostProcessInput) -> Bool {
        guard let snap = input.snapshot else { return input.midSentence }
        if snap.atStart { return false }
        if let before = snap.before, before == "\n" || before == "\r" { return false }
        guard let ch = snap.lastNonSpaceBefore else { return input.midSentence }
        if ".?!…".contains(ch) { return false }
        if "•·●-*".contains(ch), snap.lastNonSpaceIsAtLineStart { return false }
        return true
    }
}
