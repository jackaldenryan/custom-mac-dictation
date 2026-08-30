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
        if AppRuntime.isLocalTest {
            _ = Permissions.accessibilityGranted(prompt: true)
        }
        DiagnosticLog.line("Launch version \(AppVersion.current) ax=\(Permissions.accessibilityGranted(prompt: false)) local=\(AppRuntime.isLocalTest)")
        sleepObserver.onWillSleep = { [weak self] in
            Task { await self?.session.stopCompletely(persist: false) }
        }
        sleepObserver.onScreenUnlocked = { [weak self] in
            guard let self else { return }
            Task {
                if self.store.settings.preferredListeningState != .off {
                    await self.session.startListening()
                }
            }
        }
        sleepObserver.start()

        if store.settings.hasCompletedOnboarding {
            presentStatusItem()
            showMainWindow()
            if store.settings.launchAtLogin, !AppRuntime.isLocalTest {
                try? SMAppService.mainApp.register()
            }
            Task {
                await session.restorePreferredState()
                if !AppRuntime.isLocalTest {
                    await updater.check(interactive: false)
                }
            }
        } else {
            NSApp.setActivationPolicy(.regular)
            onboarding.show(session: session, store: store) { [weak self] in
                self?.presentStatusItem()
                self?.showMainWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if store.settings.hasCompletedOnboarding {
            showMainWindow()
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
        appMenu.addItem(withTitle: "Hide Custom Dictation", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Custom Dictation", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: Selector(("delete:")), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

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

    private func showMainWindow() {
        mainWindow.show(session: session, store: store, updater: updater)
    }

    private func presentStatusItem() {
        guard statusItem == nil else { return }
        statusItem = StatusItemController(session: session, updater: updater) { [weak self] in
            self?.showMainWindow()
        }
    }
}
