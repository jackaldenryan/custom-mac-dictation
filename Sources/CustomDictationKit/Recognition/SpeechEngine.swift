import AVFoundation
import CoreMedia
import Foundation
import Speech

public final class SpeechEngine: @unchecked Sendable {
    public var onFinalTranscript: (@Sendable (String) -> Void)?
    public var onPartialTranscript: (@Sendable (String) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?
    public var onAssetProgress: (@Sendable (Double) -> Void)?

    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var detector: SpeechDetector?
    private var capture: AudioCapture?
    private var resultsTask: Task<Void, Never>?
    private var detectorTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var finalizeTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var lastInputEnd = CMTime.zero
    private var lastSpeechEnd = CMTime.zero
    private var lastVolatileAt = Date.distantPast
    private var pendingFinalize = false
    private var bufferCount = 0
    public var finalizeDelaySeconds = AppSettings.defaultFinalizeDelaySeconds

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

        var reporting = preset.reportingOptions
        reporting.insert(.volatileResults)
        reporting.insert(.frequentFinalization)

        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: hints,
            transcriptionOptions: preset.transcriptionOptions.union([.punctuation]),
            reportingOptions: reporting,
            attributeOptions: preset.attributeOptions
        )
        let detector = SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: true)
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

        let preferredFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
        let compatibleFormats = await transcriber.availableCompatibleAudioFormats
        let format = preferredFormat ?? compatibleFormats.first
        guard let format else {
            throw NSError(
                domain: "SpeechEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No compatible speech audio format."]
            )
        }
        try await analyzer.prepareToAnalyze(in: format)
        DiagnosticLog.line("Analyzer ready format=\(format.sampleRate)Hz ch=\(format.channelCount)")

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        inputContinuation = continuation
        lastInputEnd = .zero
        lastSpeechEnd = .zero
        bufferCount = 0

        let capture = AudioCapture(deviceUID: microphoneUID, outputFormat: format) { [weak self] buffer, startTime in
            guard let self else { return }
            let duration = CMTime(value: CMTimeValue(buffer.frameLength), timescale: CMTimeScale(buffer.format.sampleRate))
            let end = CMTimeAdd(startTime, duration)
            self.lastInputEnd = end
            self.bufferCount += 1
            if self.bufferCount == 1 || self.bufferCount % 200 == 0 {
                DiagnosticLog.line("Audio buffers=\(self.bufferCount) end=\(end.seconds)")
            }
            continuation.yield(AnalyzerInput(buffer: buffer, bufferStartTime: startTime))
        }
        try capture.start()

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    DiagnosticLog.line(
                        "Transcript final=\(result.isFinal) t=\(result.resultsFinalizationTime.seconds) text=\(text)"
                    )
                    if result.isFinal {
                        self?.onFinalTranscript?(text)
                    } else {
                        self?.lastVolatileAt = Date()
                        self?.pendingFinalize = true
                        self?.onPartialTranscript?(text)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                DiagnosticLog.line("Transcript stream error: \(error.localizedDescription)")
                self?.onError?(error)
            }
        }

        detectorTask = Task { [weak self] in
            do {
                for try await result in detector.results {
                    guard let self else { return }
                    if result.speechDetected {
                        self.lastSpeechEnd = result.range.end
                    } else if result.isFinal || result.range.end.isValid {
                        self.lastSpeechEnd = result.range.end
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                DiagnosticLog.line("Speech detector error: \(error.localizedDescription)")
            }
        }

        finalizeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.pendingFinalize else { continue }
                if Date().timeIntervalSince(self.lastVolatileAt) >= self.finalizeDelaySeconds {
                    await self.finalizeThroughLatest()
                }
            }
        }

        analysisTask = Task { [weak self] in
            do {
                DiagnosticLog.line("Analyzer start")
                try await analyzer.start(inputSequence: stream)
                DiagnosticLog.line("Analyzer start returned")
            } catch is CancellationError {
                return
            } catch {
                DiagnosticLog.line("Analyzer start error: \(error.localizedDescription)")
                self?.onError?(error)
            }
        }

        self.analyzer = analyzer
        self.transcriber = transcriber
        self.detector = detector
        self.capture = capture
    }

    public func stop() async {
        finalizeTask?.cancel()
        finalizeTask = nil
        resultsTask?.cancel()
        resultsTask = nil
        detectorTask?.cancel()
        detectorTask = nil
        inputContinuation?.finish()
        inputContinuation = nil
        capture?.stop()
        capture = nil
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        analysisTask?.cancel()
        analysisTask = nil
        analyzer = nil
        transcriber = nil
        detector = nil
        pendingFinalize = false
        DiagnosticLog.line("Engine stopped after \(bufferCount) buffers")
    }

    private func finalizeThroughLatest() async {
        pendingFinalize = false
        guard let analyzer else { return }
        var through = lastInputEnd
        if lastSpeechEnd.isValid, lastSpeechEnd.isNumeric {
            through = CMTimeMaximum(through, lastSpeechEnd)
        }
        guard through.isValid, through.isNumeric, through.seconds > 0 else { return }
        do {
            DiagnosticLog.line("Finalize through \(through.seconds)")
            try await analyzer.finalize(through: through)
        } catch {
            DiagnosticLog.line("Finalize error: \(error.localizedDescription)")
        }
    }

    private func resolvedLocale() async -> Locale {
        await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US"))
            ?? Locale(identifier: "en_US")
    }
}
