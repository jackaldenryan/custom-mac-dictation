import AppKit

@MainActor
public final class SleepObserver {
    private var tokens: [NSObjectProtocol] = []
    public var onWillSleep: (() -> Void)?

    public init() {}

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onWillSleep?() }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onWillSleep?() }
        })
    }
}
