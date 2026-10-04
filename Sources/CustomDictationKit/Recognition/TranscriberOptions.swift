import Foundation
import Speech

/// The DictationTranscriber options the app runs with, shared by the app's
/// SpeechEngine and the ProbeSpeech tool so both test the same thing.
///
/// Automatic punctuation is OFF by default (Oct 3): Apple's model guessed
/// marks at pauses ("or is it just? Something", "issue though. Is that").
/// With it off, marks come only from spoken punctuation ("period",
/// "comma", "question mark"), like Voice Control.
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
}
