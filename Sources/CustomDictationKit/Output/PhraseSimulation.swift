import Foundation

public enum PhraseSimulation {
    public static func typed(
        into field: String,
        at utf16Offset: Int? = nil,
        selectedLength: Int = 0,
        transcript: String,
        pendingLeadSpace: Bool = false,
        isPartial: Bool = false
    ) -> String? {
        apply(
            DefaultPostProcess.apply,
            into: field,
            at: utf16Offset,
            selectedLength: selectedLength,
            transcript: transcript,
            pendingLeadSpace: pendingLeadSpace,
            isPartial: isPartial
        )
    }

    public static func typedJavaScript(
        into field: String,
        at utf16Offset: Int? = nil,
        selectedLength: Int = 0,
        transcript: String,
        pendingLeadSpace: Bool = false,
        isPartial: Bool = false
    ) throws -> String? {
        try applyThrows(
            { try PostProcessor.runJavaScript(DefaultPostProcess.javascriptSource, input: $0) },
            into: field,
            at: utf16Offset,
            selectedLength: selectedLength,
            transcript: transcript,
            pendingLeadSpace: pendingLeadSpace,
            isPartial: isPartial
        )
    }

    public static func input(
        into field: String,
        at utf16Offset: Int? = nil,
        selectedLength: Int = 0,
        transcript: String,
        pendingLeadSpace: Bool = false,
        isPartial: Bool = false
    ) -> PostProcessInput {
        let loc = utf16Offset ?? field.utf16.count
        let snap = InsertionContext.snapshot(in: field, utf16Location: loc, utf16Length: selectedLength)
        return PostProcessInput(
            text: transcript,
            isPartial: isPartial,
            pendingLeadSpace: pendingLeadSpace,
            midSentence: !InsertionContext.impliesSentenceStart(snap),
            snapshot: snap
        )
    }

    private static func apply(
        _ fn: (PostProcessInput) -> String?,
        into field: String,
        at utf16Offset: Int?,
        selectedLength: Int,
        transcript: String,
        pendingLeadSpace: Bool,
        isPartial: Bool
    ) -> String? {
        fn(
            input(
                into: field,
                at: utf16Offset,
                selectedLength: selectedLength,
                transcript: transcript,
                pendingLeadSpace: pendingLeadSpace,
                isPartial: isPartial
            )
        )
    }

    private static func applyThrows(
        _ fn: (PostProcessInput) throws -> String?,
        into field: String,
        at utf16Offset: Int?,
        selectedLength: Int,
        transcript: String,
        pendingLeadSpace: Bool,
        isPartial: Bool
    ) throws -> String? {
        try fn(
            input(
                into: field,
                at: utf16Offset,
                selectedLength: selectedLength,
                transcript: transcript,
                pendingLeadSpace: pendingLeadSpace,
                isPartial: isPartial
            )
        )
    }
}
