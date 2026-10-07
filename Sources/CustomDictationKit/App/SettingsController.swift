import Combine
import Foundation

@MainActor
public final class UpdateController: ObservableObject {
    @Published public var message = "Current version \(AppVersion.current)."
    @Published public var checking = false
    @Published public var pending: AvailableUpdate?
    @Published public var installing = false
    /// Versions the user said "Not now" to, and when.
    private var dismissed: [String: Date] = [:]
    private var periodicTask: Task<Void, Never>?
    private let prompt = UpdatePromptController()

    /// Checks now and every five minutes; a new version shows a small
    /// pop-up in the bottom-right corner.
    @MainActor
    public func startPeriodicChecks() {
        guard periodicTask == nil else { return }
        periodicTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.checkAndPrompt()
                try? await Task.sleep(for: .seconds(UpdatePromptPolicy.checkInterval))
            }
        }
    }

    @MainActor
    private func checkAndPrompt() async {
        guard !installing else { return }
        await check(interactive: false)
        guard let update = pending,
              UpdatePromptPolicy.shouldShow(version: update.version, dismissed: dismissed, now: Date(), alreadyShowing: prompt.isShowing)
        else { return }
        DiagnosticLog.line("Update \(update.version) available: showing pop-up")
        prompt.show(
            version: update.version,
            onUpdate: { [weak self] in
                Task { await self?.installPending() }
            },
            onNotNow: { [weak self] in
                self?.dismissed[update.version] = Date()
                DiagnosticLog.line("Update \(update.version): not now")
            }
        )
    }

    @MainActor
    public func check(interactive: Bool) async {
        checking = true
        if interactive {
            message = "Checking for updates…"
        }
        let result = await UpdateChecker.check()
        checking = false
        switch result {
        case .upToDate(let version):
            pending = nil
            if interactive {
                message = "Version \(version) is up to date."
            }
        case .available(let update):
            pending = update
            message = "Version \(update.version) is available."
        case .failed(let error):
            if interactive {
                message = error
            }
        }
    }

    @MainActor
    public func installPending() async {
        guard let pending else { return }
        installing = true
        do {
            try await UpdateChecker.install(pending)
        } catch {
            message = error.localizedDescription
            installing = false
        }
    }
}
