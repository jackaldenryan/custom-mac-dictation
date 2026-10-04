import Foundation

/// Runs the post-process against a fake field (text + caret), no speech or
/// AX involved. Used by CheckPhraseRules and CheckFieldScenarios.
public enum PhraseSimulation {
    public static func typed(
        into field: String,
        at utf16Offset: Int? = nil,
        selectedLength: Int = 0,
        transcript: String,
        pendingLeadSpace: Bool = false
    ) -> String? {
        DefaultPostProcess.apply(
            input(
                into: field,
                at: utf16Offset,
                selectedLength: selectedLength,
                transcript: transcript,
                pendingLeadSpace: pendingLeadSpace
            )
        )
    }

    public static func input(
        into field: String,
        at utf16Offset: Int? = nil,
        selectedLength: Int = 0,
        transcript: String,
        pendingLeadSpace: Bool = false
    ) -> PostProcessInput {
        let loc = utf16Offset ?? field.utf16.count
        let snap = InsertionContext.snapshot(in: field, utf16Location: loc, utf16Length: selectedLength)
        return PostProcessInput(
            text: transcript,
            pendingLeadSpace: pendingLeadSpace,
            midSentence: !InsertionContext.impliesSentenceStart(snap),
            snapshot: snap
        )
    }
}
