import AppKit

@MainActor
public final class StatusItemController: NSObject {
    private let item: NSStatusItem
    private let session: ListeningSession
    private let store: SettingsStore
    private let onOpenSettings: () -> Void
    private var flashWork: DispatchWorkItem?

    public init(session: ListeningSession, store: SettingsStore = .shared, onOpenSettings: @escaping () -> Void) {
        self.session = session
        self.store = store
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

        if session.state == .listening {
            menu.addItem(actionItem("Stop Listening", #selector(stopListening)))
        } else {
            menu.addItem(actionItem("Start Listening", #selector(startListening)))
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
        menu.addItem(actionItem("Quit Custom Dictation", #selector(quit)))
        item.menu = menu
    }

    private var stateTitle: String {
        switch session.state {
        case .off, .suspended: return "Listening is off"
        case .listening: return "Listening"
        }
    }

    private func actionItem(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func refreshIcon() {
        let name = session.state == .listening ? "mic.fill" : "mic.slash"
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

    @objc private func chooseMicrophone(_ sender: NSMenuItem) {
        let uid = sender.representedObject as? String
        let value = (uid?.isEmpty == false) ? uid : nil
        _ = store.update { $0.microphoneUID = value }
        rebuildMenu()
        if session.state == .listening {
            Task { await session.startListening() }
        }
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
