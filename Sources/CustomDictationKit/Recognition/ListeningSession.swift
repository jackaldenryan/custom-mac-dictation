import Combine
import Foundation

public enum ListeningState: String, Sendable {
    case off
    case suspended
    case listening
}

@MainActor
public final class ListeningSession: ObservableObject {
    @Published public private(set) var state: ListeningState = .off
    @Published public private(set) var lastPartial = ""
    @Published public private(set) var lastFinal = ""
    @Published public private(set) var lastRoute = ""
    @Published public var lastError = ""
    public var onStateChange: ((ListeningState) -> Void)?
    public var onErrorMessage: ((String) -> Void)?

    private let engine = SpeechEngine()
    private let store: SettingsStore
    private var startGeneration = 0

    public init(store: SettingsStore = .shared) {
        self.store = store
        engine.onFinalTranscript = { [weak self] text in
            Task { @MainActor in
                self?.handle(transcript: text)
            }
        }
        engine.onPartialTranscript = { [weak self] text in
            Task { @MainActor in
                self?.lastPartial = text
            }
        }
        engine.onError = { [weak self] error in
            Task { @MainActor in
                DiagnosticLog.line("Session error: \(error.localizedDescription)")
                self?.lastError = error.localizedDescription
                self?.onErrorMessage?(error.localizedDescription)
                self?.setState(.off)
            }
        }
    }

    public func ensureAssets() async throws {
        try await engine.ensureAssets()
    }

    public func startListening() async {
        startGeneration += 1
        let generation = startGeneration
        lastError = ""
        DiagnosticLog.line("Start listening requested")
        do {
            let settings = store.settings
            try await engine.start(
                microphoneUID: settings.microphoneUID,
                vocabulary: settings.vocabulary,
                commandPhrases: settings.commands.flatMap(\.phrases) + Self.builtInPhrases + AppNameResolver.commandPhrases()
            )
            guard generation == startGeneration else { return }
            setState(.listening)
            DiagnosticLog.line("Listening")
        } catch {
            DiagnosticLog.line("Start failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            onErrorMessage?(error.localizedDescription)
            setState(.off)
        }
    }

    public func suspend() {
        guard state == .listening else { return }
        setState(.suspended)
        DiagnosticLog.line("Suspended")
    }

    public func resumeFromSuspend() {
        guard state == .suspended else { return }
        setState(.listening)
        DiagnosticLog.line("Resumed")
    }

    public func stopCompletely() async {
        startGeneration += 1
        await engine.stop()
        setState(.off)
        DiagnosticLog.line("Stopped")
    }

    private func handle(transcript: String) {
        lastFinal = transcript
        lastPartial = ""
        let settings = store.settings
        let result = Router.handle(
            transcript: transcript,
            state: state,
            settings: settings,
            onStartListening: { [weak self] in self?.resumeFromSuspend() },
            onStopListening: { [weak self] in self?.suspend() }
        )
        switch result {
        case .handled:
            lastRoute = "command"
            playHandledSound(for: transcript)
        case .typed:
            lastRoute = "typed"
        case .ignored:
            lastRoute = "ignored"
        case .failed(let message):
            lastRoute = "failed"
            lastError = message
            SpokenFeedback.shared.say(message)
            onErrorMessage?(message)
        }
        DiagnosticLog.line("Route \(lastRoute) state=\(state.rawValue) text=\(transcript)")
    }

    private func playHandledSound(for transcript: String) {
        switch TranscriptNormalizer.normalize(transcript) {
        case "start listening mac":
            SoundFeedback.playStart()
        case "stop listening mac":
            SoundFeedback.playStop()
        default:
            SoundFeedback.playCommand()
        }
    }

    private static let builtInPhrases: [String] = {
        var phrases = [
            "start listening Mac",
            "stop listening Mac",
            "press",
            "open",
            "quit",
            "capitalize that",
            "uppercase that",
            "lowercase that"
        ]
        phrases.append(contentsOf: PunctuationPolicy.table.flatMap(\.names))
        return phrases
    }()

    private func setState(_ newState: ListeningState) {
        state = newState
        onStateChange?(newState)
    }
}
