import Combine
import Foundation

public enum ListeningState: String, Codable, Sendable {
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
    /// Microphones plugged in now, kept current as devices come and go.
    @Published public private(set) var microphones: [MicrophoneDevice] = []
    /// Name of the input capture is using ("" when off).
    @Published public private(set) var microphoneInUse = ""
    public var onStateChange: ((ListeningState) -> Void)?
    public var onErrorMessage: ((String) -> Void)?

    private let engine = SpeechEngine()
    private let store: SettingsStore
    private var startGeneration = 0
    /// Which input capture is using (MicrophonePriority.inputKey).
    private var inputKey: String?
    private var micWatcher: MicrophoneWatcher?
    private var micChangeTask: Task<Void, Never>?
    private var earlyCommandTask: Task<Void, Never>?
    private var earlyCommandText = ""
    private var ranEarly: EarlyCommand.Ran?
    /// Latest live text of the phrase being heard, kept until its final
    /// arrives (lastPartial can be cleared earlier by a finalize).
    private var phraseLive = ""

    /// Hold-to-talk: .held while the key is down (nothing is typed yet),
    /// .releasing while the last words are finished and typed, .discarding
    /// when the key was used for a shortcut.
    private enum HoldPhase { case idle, held, releasing, discarding }
    private var holdPhase: HoldPhase = .idle
    /// Finals heard while the key is held; typed on release.
    private var holdQueue: [String] = []
    private var holdGeneration = 0
    private var holdStart: Task<Void, Never>?
    private var holdFinalArrived = false
    private var holdMonitor: HoldKeyMonitor?
    /// False when hold-to-talk is on but the keyboard can't be watched.
    @Published public private(set) var holdKeyWatching = false

    public init(store: SettingsStore = .shared) {
        self.store = store
        engine.onFinalTranscript = { [weak self] text in
            Task { @MainActor in
                self?.handle(transcript: text)
            }
        }
        engine.onPartialTranscript = { [weak self] text in
            Task { @MainActor in
                self?.handlePartial(text)
            }
        }
        engine.onFinalizeIdle = { [weak self] in
            Task { @MainActor in
                self?.clearStaleHearing()
            }
        }
        microphones = AudioCapture.listMicrophones()
        micWatcher = MicrophoneWatcher { [weak self] in
            self?.microphonesChanged()
        }
        engine.onError = { [weak self] error in
            Task { @MainActor in
                DiagnosticLog.line("Session error: \(error.localizedDescription)")
                self?.lastError = error.localizedDescription
                self?.onErrorMessage?(error.localizedDescription)
                self?.setState(.off, persist: false)
            }
        }
    }

    public func ensureAssets() async throws {
        try await engine.ensureAssets()
    }

    public func startListening(persist: Bool = true) async {
        startGeneration += 1
        let generation = startGeneration
        lastError = ""
        DiagnosticLog.line("Start listening requested")
        setState(.listening, persist: persist)
        do {
            let settings = store.settings
            engine.finalizeDelaySeconds = settings.finalizeDelaySeconds
            engine.disableForcedFinalize = settings.disableFinalizeDelay
            let mic = chooseMicrophone()
            inputKey = mic.key
            microphoneInUse = mic.label
            DiagnosticLog.line("Microphone: \(mic.label)")
            try await engine.start(
                microphoneUID: mic.uid,
                vocabulary: settings.vocabulary.filter(\.enabled),
                commandPhrases: Self.commandPhrases(settings)
            )
            guard generation == startGeneration else { return }
            DiagnosticLog.line("Listening")
            refreshMicrophone() // a mic may have come or gone while starting
        } catch {
            guard generation == startGeneration else { return }
            DiagnosticLog.line("Start failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            onErrorMessage?(error.localizedDescription)
            setState(.off, persist: false)
        }
    }

    private static func commandPhrases(_ settings: AppSettings) -> [String] {
        settings.commands.filter(\.enabled).flatMap(\.phrases).map {
            $0.replacingOccurrences(of: " {app}", with: "").replacingOccurrences(of: "{app}", with: "")
        } + AppNameResolver.commandPhrases()
    }

    // MARK: Hold-to-talk

    /// Starts or stops watching the hold key to match the settings. Call at
    /// launch and whenever hold-to-talk settings change.
    public func applyHoldToTalk() {
        let hold = store.settings.holdToTalk
        guard hold.enabled else {
            holdMonitor?.stop()
            holdMonitor = nil
            holdKeyWatching = false
            return
        }
        if let monitor = holdMonitor, monitor.key == hold.key, holdKeyWatching { return }
        holdMonitor?.stop()
        let monitor = HoldKeyMonitor(key: hold.key) { [weak self] action in
            Task { @MainActor in
                switch action {
                case .begin: self?.holdKeyDown()
                case .end(let cancelled): self?.holdKeyUp(cancelled: cancelled)
                case .none: break
                }
            }
        }
        holdKeyWatching = monitor.start()
        holdMonitor = monitor
    }

    /// Turning hold-to-talk on stops always-on listening; turning it off
    /// starts it.
    public func setHoldToTalk(enabled: Bool) async {
        _ = store.update { $0.holdToTalk.enabled = enabled }
        applyHoldToTalk()
        if enabled {
            if state != .off { await stopCompletely(persist: true) }
            await prewarm()
        } else {
            await startListening()
        }
    }

    /// Loads the speech model without opening the mic, so the first hold
    /// hears from the start.
    public func prewarm() async {
        guard state == .off else { return }
        let settings = store.settings
        try? await engine.start(
            microphoneUID: chooseMicrophone().uid,
            vocabulary: settings.vocabulary.filter(\.enabled),
            commandPhrases: Self.commandPhrases(settings),
            capture: false
        )
        DiagnosticLog.line("Hold-to-talk ready")
    }

    func holdKeyDown() {
        guard store.settings.holdToTalk.enabled else { return }
        // Already listening all the time (started from the menu or by voice).
        if holdPhase == .idle, state == .listening { return }
        holdGeneration += 1
        holdPhase = .held
        holdQueue = []
        DiagnosticLog.line("Hold key down: listening")
        holdStart = Task { [weak self] in
            await self?.startListening(persist: false)
        }
    }

    func holdKeyUp(cancelled: Bool) {
        guard holdPhase == .held else { return }
        let generation = holdGeneration
        holdPhase = cancelled ? .discarding : .releasing
        DiagnosticLog.line(cancelled ? "Hold key used in a shortcut: discarding" : "Hold key up: typing what was heard")
        Task { [weak self] in
            await self?.finishHold(generation: generation, cancelled: cancelled)
        }
    }

    private func finishHold(generation: Int, cancelled: Bool) async {
        await holdStart?.value
        guard generation == holdGeneration else { return }
        if cancelled {
            holdQueue = []
        } else {
            let queued = holdQueue
            holdQueue = []
            for text in queued { process(final: text) }
            holdFinalArrived = false
            let spoke = !lastPartial.isEmpty
            await engine.finalizeNow()
            // Wait for the last words' final (it can land just after).
            let deadline = Date().addingTimeInterval(spoke ? 1.5 : 0.3)
            while !holdFinalArrived, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(50))
                guard generation == holdGeneration else { return }
            }
        }
        guard generation == holdGeneration else { return }
        holdPhase = .idle
        await stopCompletely(persist: false)
    }

    public func suspend() {
        guard state == .listening else { return }
        LivePhrase.keepAndUnhighlight()
        setState(.suspended, persist: true)
        DiagnosticLog.line("Suspended")
    }

    public func resumeFromSuspend() {
        guard state == .suspended else { return }
        setState(.listening, persist: true)
        DiagnosticLog.line("Resumed")
    }

    public func stopCompletely(persist: Bool = true) async {
        startGeneration += 1
        LivePhrase.keepAndUnhighlight()
        setState(.off, persist: persist)
        await engine.stop()
        inputKey = nil
        microphoneInUse = ""
        DiagnosticLog.line("Stopped")
    }

    /// The first listed microphone that is plugged in, else the system default.
    private func chooseMicrophone() -> (uid: String?, key: String, label: String) {
        let available = AudioCapture.listMicrophones()
        let resolved = MicrophonePriority.resolve(store.settings.microphonePriority, available: available)
        let key = MicrophonePriority.inputKey(resolved: resolved, systemDefaultUID: AudioCapture.defaultInputUID())
        guard let resolved else { return (nil, key, "system default") }
        let name = available.first { $0.uid == resolved.uid }?.name ?? resolved.name
        return (resolved.uid, key, name)
    }

    /// A mic was plugged in or removed: wait for the burst of CoreAudio
    /// notifications to settle, then move capture if the choice changed.
    private func microphonesChanged() {
        micChangeTask?.cancel()
        micChangeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.microphones = AudioCapture.listMicrophones()
            self.refreshMicrophone()
        }
    }

    /// Re-picks the microphone (after a device change or a settings change)
    /// and moves capture to it when it differs from the one in use.
    public func refreshMicrophone() {
        guard state != .off, inputKey != nil, engine.isRunning else { return }
        let mic = chooseMicrophone()
        guard mic.key != inputKey else { return }
        inputKey = mic.key
        microphoneInUse = mic.label
        DiagnosticLog.line("Microphone changed: \(mic.label)")
        do {
            try engine.switchMicrophone(to: mic.uid)
        } catch {
            DiagnosticLog.line("Microphone switch failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            onErrorMessage?(error.localizedDescription)
        }
    }

    public func setFinalizeDelay(_ seconds: Double) {
        engine.finalizeDelaySeconds = AppSettings.clampedFinalizeDelay(seconds)
        engine.disableForcedFinalize = store.settings.disableFinalizeDelay
    }

    public func requestStart() async {
        switch state {
        case .listening:
            return
        case .suspended:
            resumeFromSuspend()
        case .off:
            await startListening()
        }
    }

    public func requestStop() {
        if state == .listening { suspend() }
    }

    public func restorePreferredState() async {
        applyHoldToTalk()
        if store.settings.holdToTalk.enabled {
            await prewarm()
            return
        }
        switch store.settings.preferredListeningState {
        case .off:
            return
        case .listening:
            await startListening()
        case .suspended:
            await startListening()
            suspend()
        }
    }

    private func handlePartial(_ text: String) {
        let repeated = text == lastPartial
        lastPartial = text
        phraseLive = text
        // Apple can resend the same live text; that must not restart the wait.
        if !(repeated && text == earlyCommandText) {
            earlyCommandTask?.cancel()
            earlyCommandText = ""
        }
        guard state == .listening else { return }
        // Hold-to-talk types on release (keystrokes sent while a modifier
        // is held would become shortcuts).
        if holdPhase != .idle { return }
        if Router.shouldHoldLive(transcript: text, state: state, settings: store.settings) {
            if earlyCommandText != text, Router.isEarlyCommand(transcript: text, state: state, settings: store.settings) {
                scheduleEarlyCommand(text)
            }
            return
        }
        LivePhrase.show(text)
    }

    /// Commands used to wait for Apple's final, 1-2 s after you stop
    /// talking. A live transcript that is already a whole command runs once
    /// it has been stable for `commandSettleSeconds`; its final is
    /// then skipped (see EarlyCommand.resolveFinal).
    private func scheduleEarlyCommand(_ text: String) {
        earlyCommandText = text
        let settle = store.settings.commandSettleSeconds
        earlyCommandTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(settle * 1000)))
            guard !Task.isCancelled, let self, self.state == .listening, self.lastPartial == text else { return }
            self.ranEarly = EarlyCommand.Ran(normalized: TranscriptNormalizer.normalize(text), at: Date())
            DiagnosticLog.line("Command from live text (not waiting for final) text=\(text)")
            self.route(text)
            await self.engine.finalizeNow()
        }
    }

    private func clearStaleHearing() {
        lastPartial = ""
    }

    private func handle(transcript rawFinal: String) {
        // Apple's final can cut off the start the live text showed.
        let transcript = FinalReconcile.restoreDroppedStart(live: phraseLive, final: rawFinal)
        phraseLive = ""
        if transcript != rawFinal {
            DiagnosticLog.line("Final lost its start; kept the live words: \(String(reflecting: rawFinal)) -> \(String(reflecting: transcript))")
        }
        process(final: transcript)
    }

    private func process(final transcript: String) {
        switch holdPhase {
        case .held:
            holdQueue.append(transcript)
            lastPartial = ""
            return
        case .discarding:
            lastPartial = ""
            DiagnosticLog.line("Discarded (hold key used in a shortcut) text=\(transcript)")
            return
        case .releasing:
            holdFinalArrived = true
        case .idle:
            break
        }
        earlyCommandTask?.cancel()
        earlyCommandText = ""
        lastPartial = ""
        let ran = ranEarly
        ranEarly = nil
        switch EarlyCommand.resolveFinal(transcript, ran: ran, now: Date()) {
        case .skip:
            lastFinal = transcript
            DiagnosticLog.line("Route command (already ran from live text) text=\(transcript)")
            return
        case .route(let rest):
            route(rest)
        }
    }

    private func route(_ transcript: String) {
        lastFinal = transcript
        let settings = store.settings
        let result = Router.handle(
            transcript: transcript,
            state: state,
            settings: settings,
            onStartListening: { [weak self] in
                Task { await self?.requestStart() }
            },
            onStopListening: { [weak self] in
                self?.requestStop()
            }
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
            let sounds = settings.sounds
            SoundFeedback.play(.commandFailed, settings: sounds)
            if sounds.speakFailures {
                SpokenFeedback.shared.say(message)
            }
            onErrorMessage?(message)
        }
        DiagnosticLog.line("Route \(lastRoute) state=\(state.rawValue) text=\(transcript)")
    }

    private func playHandledSound(for transcript: String) {
        let normalized = TranscriptNormalizer.normalize(transcript)
        let commands = store.settings.commands.filter(\.enabled)
        if commands.contains(where: { $0.action == .startListening && $0.phrases.contains { TranscriptNormalizer.normalize($0) == normalized } }) {
            SoundFeedback.play(.startListening, settings: store.settings.sounds)
        } else if commands.contains(where: { $0.action == .stopListening && $0.phrases.contains { TranscriptNormalizer.normalize($0) == normalized } }) {
            SoundFeedback.play(.stopListening, settings: store.settings.sounds)
        } else {
            SoundFeedback.play(.commandRan, settings: store.settings.sounds)
        }
    }

    private func setState(_ newState: ListeningState, persist: Bool) {
        state = newState
        if persist {
            _ = store.update { $0.preferredListeningState = newState }
        }
        onStateChange?(newState)
    }
}
