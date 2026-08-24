import AppKit

@MainActor
public final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private let session: ListeningSession
    private let onOpenSettings: () -> Void
    private var flashWork: DispatchWorkItem?

    public init(session: ListeningSession, onOpenSettings: @escaping () -> Void) {
        self.session = session
        self.onOpenSettings = onOpenSettings
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.imagePosition = .imageOnly
        rebuildMenu()
        refreshIcon()
        session.onStateChange = { [weak self] _ in
            self?.rebuildMenu()
            self?.refreshIcon()
        }
        session.onErrorMessage = { [weak self] _ in
            self?.flashError()
        }
    }

    public func rebuildMenu() {
        let menu = NSMenu()
        let stateItem = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        if session.state == .off {
            menu.addItem(actionItem("Start Listening", #selector(startListening)))
        } else {
            menu.addItem(actionItem("Stop Listening", #selector(stopListening)))
        }
        if session.state == .listening {
            menu.addItem(actionItem("Suspend", #selector(suspend)))
        } else if session.state == .suspended {
            menu.addItem(actionItem("Resume Listening", #selector(startListening)))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Settings…", #selector(openSettings)))
        menu.addItem(actionItem("Quit Custom Dictation", #selector(quit)))
        item.menu = menu
    }

    private var stateTitle: String {
        switch session.state {
        case .off: return "Listening is off"
        case .suspended: return "Listening is paused"
        case .listening: return "Listening"
        }
    }

    private func actionItem(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func refreshIcon() {
        let name: String
        switch session.state {
        case .off: name = "mic.slash"
        case .suspended: name = "pause.circle"
        case .listening: name = "mic.fill"
        }
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: stateTitle)
    }

    private func flashError() {
        item.button?.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error")
        flashWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshIcon() }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    @objc private func startListening() {
        Task { await session.startListening() }
    }

    @objc private func stopListening() {
        Task { await session.stopCompletely() }
    }

    @objc private func suspend() {
        session.suspend()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
