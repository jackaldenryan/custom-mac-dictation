import Foundation

public enum ListeningState: String, Sendable {
    case off
    case suspended
    case listening
}

@MainActor
public final class ListeningSession {
    public private(set) var state: ListeningState = .off
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
        engine.onError = { [weak self] error in
            Task { @MainActor in
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
        do {
            let settings = store.settings
            try await engine.start(
                microphoneUID: settings.microphoneUID,
                vocabulary: settings.vocabulary,
                commandPhrases: settings.commands.flatMap(\.phrases) + [
                    "start listening Mac",
                    "stop listening Mac",
                    "press",
                    "open",
                    "quit",
                    "capitalize that",
                    "uppercase that",
                    "lowercase that"
                ]
            )
            guard generation == startGeneration else { return }
            setState(.listening)
        } catch {
            onErrorMessage?(error.localizedDescription)
            setState(.off)
        }
    }

    public func suspend() {
        guard state == .listening else { return }
        setState(.suspended)
    }

    public func resumeFromSuspend() {
        guard state == .suspended else { return }
        setState(.listening)
    }

    public func stopCompletely() async {
        startGeneration += 1
        await engine.stop()
        setState(.off)
    }

    private func handle(transcript: String) {
        let settings = store.settings
        let result = Router.handle(
            transcript: transcript,
            state: state,
            settings: settings,
            onStartListening: { [weak self] in self?.resumeFromSuspend() },
            onStopListening: { [weak self] in self?.suspend() }
        )
        if case .failed(let message) = result {
            SpokenFeedback.shared.say(message)
            onErrorMessage?(message)
        }
    }

    private func setState(_ newState: ListeningState) {
        state = newState
        onStateChange?(newState)
    }
}
