import Foundation
import Speech

/// The DictationTranscriber options the app runs with, shared by the app's
/// SpeechEngine and the ProbeSpeech tool so both test the same thing.
///
/// The app always runs with automatic punctuation OFF (0.1.40): Apple's
/// model guessed marks at pauses ("or is it just? Something", "issue
/// though. Is that"). Marks come only from spoken punctuation ("period",
/// "comma", "question mark"), like Voice Control, and the typing logic
/// relies on that. `autoPunctuation: true` exists only for ProbeSpeech.
public enum TranscriberOptions {
    public static func transcription(
        preset: DictationTranscriber.Preset,
        autoPunctuation: Bool
    ) -> Set<DictationTranscriber.TranscriptionOption> {
        var options = preset.transcriptionOptions
        if autoPunctuation {
            options.insert(.punctuation)
        } else {
            options.remove(.punctuation)
        }
        return options
    }

    /// Live (volatile) results plus frequent finalization, as the app runs.
    public static func reporting(
        preset: DictationTranscriber.Preset
    ) -> Set<DictationTranscriber.ReportingOption> {
        var reporting = preset.reportingOptions
        reporting.insert(.volatileResults)
        reporting.insert(.frequentFinalization)
        return reporting
    }
}
