import AVFoundation
import CoreMedia
import Foundation
import Speech

public final class SpeechEngine: @unchecked Sendable {
    public var onFinalTranscript: (@Sendable (String) -> Void)?
    public var onPartialTranscript: (@Sendable (String) -> Void)?
    public var onFinalizeIdle: (@Sendable () -> Void)?
    public var onError: (@Sendable (Error) -> Void)?
    public var onAssetProgress: (@Sendable (Double) -> Void)?

    private var analyzer: SpeechAnalyzer?
    private var transcriber: DictationTranscriber?
    private var capture: AudioCapture?
    private var resultsTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var finalizeTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var lastInputEnd = CMTime.zero
    private var finalizeGate = FinalizeGate()
    private var bufferCount = 0
    private var outputFormat: AVAudioFormat?
    private var lastMicrophoneUID: String?
    private var lastVocabSignature = ""
    public var finalizeDelaySeconds = AppSettings.defaultFinalizeDelaySeconds
    public var disableForcedFinalize = false
    public var isRunning: Bool { capture != nil }

    public init() {}

    public func ensureAssets() async throws {
        let locale = await resolvedLocale()
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        _ = try await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            Task { @MainActor in
                self.onAssetProgress?(request.progress.fractionCompleted)
            }
            try await request.downloadAndInstall()
        }
        onAssetProgress?(1)
    }

    /// - capture: false only prepares the analyzer (hold-to-talk warms it up
    ///   at launch so the first press starts hearing right away).
    public func start(microphoneUID: String?, vocabulary: [VocabEntry], commandPhrases: [String], capture: Bool = true) async throws {
        let signature = Self.signature(vocabulary: vocabulary, phrases: commandPhrases)
        if analyzer != nil, inputContinuation != nil, lastMicrophoneUID == microphoneUID, lastVocabSignature == signature {
            if capture, self.capture == nil {
                try startCapture(microphoneUID: microphoneUID)
                DiagnosticLog.line("Capture resumed")
            }
            return
        }
        await teardown()
        lastMicrophoneUID = microphoneUID
        lastVocabSignature = signature
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

        let reporting = TranscriberOptions.reporting(preset: preset)

        let transcriber = DictationTranscriber(
            locale: locale,
            contentHints: hints,
            transcriptionOptions: TranscriberOptions.transcription(preset: preset, autoPunctuation: false),
            reportingOptions: reporting,
            attributeOptions: preset.attributeOptions
        )
        let modules: [any SpeechModule] = [transcriber]

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
        outputFormat = format
        lastInputEnd = .zero
        bufferCount = 0
        if capture {
            try startCapture(microphoneUID: microphoneUID)
        }

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty {
                        if result.isFinal {
                            self?.onFinalizeIdle?()
                        }
                        continue
                    }
                    DiagnosticLog.line(
                        "Transcript final=\(result.isFinal) t=\(result.resultsFinalizationTime.seconds) text=\(text)"
                    )
                    if result.isFinal {
                        self?.finalizeGate.noteFinal()
                        self?.onFinalTranscript?(text)
                    } else {
                        self?.finalizeGate.notePartial()
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

        finalizeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, !self.disableForcedFinalize, self.finalizeGate.shouldForceFinalize(delay: self.finalizeDelaySeconds) else { continue }
                await self.finalizeThroughLatest()
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
    }

    public func stop() async {
        pauseCapture()
        DiagnosticLog.line("Capture paused after \(bufferCount) buffers")
    }

    /// Moves capture to another microphone without rebuilding the analyzer
    /// (the capture converts any mic to the analyzer's format).
    public func switchMicrophone(to microphoneUID: String?) throws {
        guard analyzer != nil else { return }
        lastMicrophoneUID = microphoneUID
        guard capture != nil else { return }
        pauseCapture()
        try startCapture(microphoneUID: microphoneUID)
        DiagnosticLog.line("Capture moved to \(microphoneUID ?? "system default")")
    }

    private func startCapture(microphoneUID: String?) throws {
        guard capture == nil else { return }
        guard let format = outputFormat, let continuation = inputContinuation else {
            throw NSError(
                domain: "SpeechEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Speech analyzer is not ready."]
            )
        }
        let capture = AudioCapture(
            deviceUID: microphoneUID,
            outputFormat: format,
            timeBase: lastInputEnd
        ) { [weak self] buffer, startTime in
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
        self.capture = capture
    }

    private func pauseCapture() {
        capture?.stop()
        capture = nil
        finalizeGate.noteFinal()
    }

    private func teardown() async {
        pauseCapture()
        finalizeTask?.cancel()
        finalizeTask = nil
        resultsTask?.cancel()
        resultsTask = nil
        inputContinuation?.finish()
        inputContinuation = nil
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        analysisTask?.cancel()
        analysisTask = nil
        analyzer = nil
        transcriber = nil
        outputFormat = nil
        lastMicrophoneUID = nil
        lastVocabSignature = ""
        DiagnosticLog.line("Engine torn down")
    }

    private static func signature(vocabulary: [VocabEntry], phrases: [String]) -> String {
        vocabulary.map { "\($0.word)|\($0.ipa.joined(separator: ","))" }.joined(separator: ";")
            + "\n" + phrases.joined(separator: "\n")
    }

    /// End the current segment now (Apple sends its final right away).
    public func finalizeNow() async {
        await finalizeThroughLatest()
    }

    private func finalizeThroughLatest() async {
        finalizeGate.noteFinal()
        guard let analyzer else { return }
        let through = lastInputEnd
        guard through.isValid, through.isNumeric, through.seconds > 0 else { return }
        do {
            DiagnosticLog.line("Finalize through \(through.seconds)")
            try await analyzer.finalize(through: through)
            onFinalizeIdle?()
        } catch {
            DiagnosticLog.line("Finalize error: \(error.localizedDescription)")
            onFinalizeIdle?()
        }
    }

    private func resolvedLocale() async -> Locale {
        await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US"))
            ?? Locale(identifier: "en_US")
    }
}
