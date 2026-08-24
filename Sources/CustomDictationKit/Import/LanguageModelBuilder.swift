import Foundation
import Speech

public enum LanguageModelBuilder {
    public static func build(
        vocabulary: [VocabEntry],
        phrases: [String],
        locale: Locale
    ) async throws -> SFSpeechLanguageModel.Configuration? {
        guard !vocabulary.isEmpty || !phrases.isEmpty else { return nil }

        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CustomDictation/LanguageModel", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let dataURL = folder.appendingPathComponent("custom.bin")
        let modelURL = folder.appendingPathComponent("model.lm")
        let vocabURL = folder.appendingPathComponent("vocab.bin")

        let allowed = Set(SFCustomLanguageModelData.supportedPhonemes(locale: locale))
        let data = SFCustomLanguageModelData(
            locale: locale,
            identifier: "com.jackaldenryan.custom-mac-dictation",
            version: AppVersion.current
        )

        for entry in vocabulary {
            let phonemes = entry.ipa.compactMap { raw in
                IPAToXSampa.filter(IPAToXSampa.convert(raw), allowed: allowed)
            }
            data.insert(term: .init(grapheme: entry.word, phonemes: phonemes))
            data.insert(phraseCount: .init(phrase: entry.word, count: 1000))
        }
        for phrase in phrases where !phrase.isEmpty {
            data.insert(phraseCount: .init(phrase: phrase, count: 800))
        }

        try await data.export(to: dataURL)
        let configuration = SFSpeechLanguageModel.Configuration(languageModel: modelURL, vocabulary: vocabURL)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            SFSpeechLanguageModel.prepareCustomLanguageModel(for: dataURL, configuration: configuration) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        return configuration
    }
}
