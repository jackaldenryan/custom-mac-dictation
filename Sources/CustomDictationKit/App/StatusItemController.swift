import AppKit

public enum StatusMenuState {
    nonisolated(unsafe) public static var isOpen = false
}

@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let session: ListeningSession
    private let store: SettingsStore
    private let updater: UpdateController
    private let onOpenSettings: () -> Void
    private var flashWork: DispatchWorkItem?

    public init(
        session: ListeningSession,
        store: SettingsStore = .shared,
        updater: UpdateController,
        onOpenSettings: @escaping () -> Void
    ) {
        self.session = session
        self.store = store
        self.updater = updater
        self.onOpenSettings = onOpenSettings
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        refreshIcon()
        session.onStateChange = { [weak self] _ in
            self?.refreshIcon()
        }
        session.onErrorMessage = { [weak self] _ in
            self?.flashError()
        }
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let stateItem = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        if session.state == .listening {
            menu.addItem(actionItem("Pause Listening", #selector(stopListening)))
        }
        if session.state != .listening {
            menu.addItem(actionItem("Start Listening", #selector(startListening)))
        }
        if session.state != .off {
            menu.addItem(actionItem("Turn Mic Off", #selector(turnMicOff)))
        }

        let micMenu = NSMenu()
        let defaultItem = NSMenuItem(title: "System default", action: #selector(chooseMicrophone(_:)), keyEquivalent: "")
        defaultItem.target = self
        defaultItem.representedObject = ""
        if store.settings.microphoneUID == nil { defaultItem.state = .on }
        micMenu.addItem(defaultItem)
        for mic in AudioCapture.listMicrophones() {
            let item = NSMenuItem(title: mic.name, action: #selector(chooseMicrophone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mic.uid
            if store.settings.microphoneUID == mic.uid { item.state = .on }
            micMenu.addItem(item)
        }
        let micRoot = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        micRoot.submenu = micMenu
        menu.addItem(micRoot)

        menu.addItem(.separator())
        menu.addItem(actionItem("Show Window", #selector(openSettings)))

        let check = actionItem(updater.checking ? "Checking for updates…" : "Check for updates", #selector(checkUpdates))
        check.isEnabled = !updater.checking && !updater.installing
        menu.addItem(check)
        if let pending = updater.pending {
            let install = actionItem(
                updater.installing ? "Installing update…" : "Install update \(pending.version)",
                #selector(installUpdate)
            )
            install.isEnabled = !updater.installing
            menu.addItem(install)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Quit \(AppRuntime.displayName)", #selector(quit)))
    }

    public func menuWillOpen(_ menu: NSMenu) {
        StatusMenuState.isOpen = true
    }

    public func menuDidClose(_ menu: NSMenu) {
        StatusMenuState.isOpen = false
    }

    private var stateTitle: String {
        switch session.state {
        case .off: return "Listening is off"
        case .suspended: return "Paused"
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
        case .listening: name = "mic.fill"
        case .suspended: name = "mic"
        case .off: name = "mic.slash"
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
        Task { await session.requestStart() }
    }

    @objc private func stopListening() {
        session.requestStop()
    }

    @objc private func turnMicOff() {
        Task { await session.stopCompletely() }
    }

    @objc private func chooseMicrophone(_ sender: NSMenuItem) {
        let uid = sender.representedObject as? String
        let value = (uid?.isEmpty == false) ? uid : nil
        _ = store.update { $0.microphoneUID = value }
        if session.state == .listening {
            Task { await session.startListening() }
        }
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func checkUpdates() {
        Task { await updater.check(interactive: true) }
    }

    @objc private func installUpdate() {
        Task { await updater.installPending() }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
