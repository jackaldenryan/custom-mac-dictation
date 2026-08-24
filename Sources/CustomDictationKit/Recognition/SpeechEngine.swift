import AVFoundation
import Foundation
import Speech

public final class SpeechEngine: @unchecked Sendable {
    public var onFinalTranscript: (@Sendable (String) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?
    public var onAssetProgress: (@Sendable (Double) -> Void)?

    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var capture: AudioCapture?
    private var resultsTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

    public init() {}

    public func ensureAssets() async throws {
        let locale = await resolvedLocale()
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: false)
        _ = try await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber, detector]) {
            Task { @MainActor in
                self.onAssetProgress?(request.progress.fractionCompleted)
            }
            try await request.downloadAndInstall()
        }
        onAssetProgress?(1)
    }

    public func start(microphoneUID: String?, vocabulary: [VocabEntry], commandPhrases: [String]) async throws {
        await stop()
        let locale = await resolvedLocale()
        _ = try await AssetInventory.reserve(locale: locale)

        let preset = DictationTranscriber.Preset.progressiveLongDictation
        var hints = preset.contentHints
        if let model = try? await LanguageModelBuilder.build(
            vocabulary: vocabulary,
            phrases: commandPhrases,
            locale: locale
        ) {
            hints.insert(.customizedLanguage(modelConfiguration: model))
        }

        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: hints,
            transcriptionOptions: preset.transcriptionOptions.union([.punctuation]),
            reportingOptions: preset.reportingOptions,
            attributeOptions: preset.attributeOptions
        )
        let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: false)
        let modules: [any SpeechModule] = [detector, transcriber]

        if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await request.downloadAndInstall()
        }

        let context = AnalysisContext()
        let contextual = vocabulary.map(\.word) + commandPhrases
        if !contextual.isEmpty {
            context.contextualStrings[.general] = contextual
        }

        let options = SpeechAnalyzer.Options(priority: .high, modelRetention: .processLifetime)
        let analyzer = SpeechAnalyzer(modules: modules, options: options)
        try await analyzer.setContext(context)

        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
        try await analyzer.prepareToAnalyze(in: format)

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputContinuation = continuation

        let capture = AudioCapture(deviceUID: microphoneUID, outputFormat: format) { buffer in
            continuation.yield(AnalyzerInput(buffer: buffer))
        }
        try capture.start()

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard result.isFinal else { continue }
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    self?.onFinalTranscript?(text)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.onError?(error)
            }
        }

        try await analyzer.start(inputSequence: stream)
        self.analyzer = analyzer
        self.transcriber = transcriber
        self.capture = capture
    }

    public func stop() async {
        resultsTask?.cancel()
        resultsTask = nil
        inputContinuation?.finish()
        inputContinuation = nil
        capture?.stop()
        capture = nil
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        analyzer = nil
        transcriber = nil
    }

    private func resolvedLocale() async -> Locale {
        await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US"))
            ?? Locale(identifier: "en_US")
    }
}
