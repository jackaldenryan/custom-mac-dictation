import Foundation

public enum PhraseSimulation {
    public static func typed(
        into field: String,
        at utf16Offset: Int? = nil,
        selectedLength: Int = 0,
        transcript: String,
        lastTypedAge: Double = 5,
        pendingLeadSpace: Bool = false,
        lonePunctuationDelay: Double = 0.4
    ) -> String? {
        apply(
            DefaultPostProcess.apply,
            into: field,
            at: utf16Offset,
            selectedLength: selectedLength,
            transcript: transcript,
            lastTypedAge: lastTypedAge,
            pendingLeadSpace: pendingLeadSpace,
            lonePunctuationDelay: lonePunctuationDelay
        )
    }

    public static func typedJavaScript(
        into field: String,
        at utf16Offset: Int? = nil,
        selectedLength: Int = 0,
        transcript: String,
        lastTypedAge: Double = 5,
        pendingLeadSpace: Bool = false,
        lonePunctuationDelay: Double = 0.4
    ) throws -> String? {
        try applyThrows(
            { try PostProcessor.runJavaScript(DefaultPostProcess.javascriptSource, input: $0) },
            into: field,
            at: utf16Offset,
            selectedLength: selectedLength,
            transcript: transcript,
            lastTypedAge: lastTypedAge,
            pendingLeadSpace: pendingLeadSpace,
            lonePunctuationDelay: lonePunctuationDelay
        )
    }

    public static func input(
        into field: String,
        at utf16Offset: Int? = nil,
        selectedLength: Int = 0,
        transcript: String,
        lastTypedAge: Double = 5,
        pendingLeadSpace: Bool = false,
        lonePunctuationDelay: Double = 0.4
    ) -> PostProcessInput {
        let loc = utf16Offset ?? field.utf16.count
        let snap = InsertionContext.snapshot(in: field, utf16Location: loc, utf16Length: selectedLength)
        return PostProcessInput(
            text: transcript,
            isPartial: false,
            pendingLeadSpace: pendingLeadSpace,
            lastTypedAge: lastTypedAge,
            lonePunctuationDelay: lonePunctuationDelay,
            isLonePunctuation: TranscriptNormalizer.isLonePunctuation(transcript),
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
        lastTypedAge: Double,
        pendingLeadSpace: Bool,
        lonePunctuationDelay: Double
    ) -> String? {
        fn(
            input(
                into: field,
                at: utf16Offset,
                selectedLength: selectedLength,
                transcript: transcript,
                lastTypedAge: lastTypedAge,
                pendingLeadSpace: pendingLeadSpace,
                lonePunctuationDelay: lonePunctuationDelay
            )
        )
    }

    private static func applyThrows(
        _ fn: (PostProcessInput) throws -> String?,
        into field: String,
        at utf16Offset: Int?,
        selectedLength: Int,
        transcript: String,
        lastTypedAge: Double,
        pendingLeadSpace: Bool,
        lonePunctuationDelay: Double
    ) throws -> String? {
        try fn(
            input(
                into: field,
                at: utf16Offset,
                selectedLength: selectedLength,
                transcript: transcript,
                lastTypedAge: lastTypedAge,
                pendingLeadSpace: pendingLeadSpace,
                lonePunctuationDelay: lonePunctuationDelay
            )
        )
    }
}
