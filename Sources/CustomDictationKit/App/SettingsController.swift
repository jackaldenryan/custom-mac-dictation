import Combine
import Foundation

public final class UpdateController: ObservableObject {
    @Published public var message = "Current version \(AppVersion.current)."
    @Published public var checking = false
    @Published public var pending: AvailableUpdate?
    @Published public var installing = false

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
