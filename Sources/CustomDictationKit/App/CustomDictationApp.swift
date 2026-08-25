import AppKit
import ServiceManagement

@MainActor
public enum CustomDictationApp {
    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.retained = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var retained: AppDelegate?

    private let store = SettingsStore.shared
    private lazy var session = ListeningSession(store: store)
    private let sleepObserver = SleepObserver()
    private let onboarding = OnboardingController()
    private let mainWindow = MainWindowController()
    private let updater = UpdateController()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        DiagnosticLog.line("Launch version \(AppVersion.current) ax=\(Permissions.accessibilityGranted(prompt: false))")
        sleepObserver.onWillSleep = { [weak self] in
            Task { await self?.session.stopCompletely() }
        }
        sleepObserver.start()

        if store.settings.hasCompletedOnboarding {
            presentMainInterface()
            if store.settings.launchAtLogin {
                try? SMAppService.mainApp.register()
            }
            Task {
                await session.startListening()
                await updater.check(interactive: false)
            }
        } else {
            onboarding.show(session: session, store: store) { [weak self] in
                self?.presentMainInterface()
                Task { await self?.session.startListening() }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if store.settings.hasCompletedOnboarding {
            presentMainInterface()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Custom Dictation", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Custom Dictation", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        let fullScreen = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        windowMenu.addItem(fullScreen)
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func presentMainInterface() {
        presentStatusItem()
        mainWindow.show(session: session, store: store, updater: updater)
    }

    private func presentStatusItem() {
        guard statusItem == nil else { return }
        statusItem = StatusItemController(session: session) { [weak self] in
            guard let self else { return }
            self.mainWindow.show(session: self.session, store: self.store, updater: self.updater)
        }
    }
}
