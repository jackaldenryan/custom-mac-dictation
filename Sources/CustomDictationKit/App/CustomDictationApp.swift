import AppKit
import ServiceManagement

@MainActor
public enum CustomDictationApp {
    public static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.retained = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
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
    private let settingsWindow = SettingsController()
    private let updater = UpdateController()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        sleepObserver.onWillSleep = { [weak self] in
            Task { await self?.session.stopCompletely() }
        }
        sleepObserver.start()

        if store.settings.hasCompletedOnboarding {
            presentStatusItem()
            if store.settings.launchAtLogin {
                try? SMAppService.mainApp.register()
            }
            Task {
                await session.startListening()
                await updater.check(interactive: false)
            }
        } else {
            onboarding.show(session: session, store: store) { [weak self] in
                self?.presentStatusItem()
                Task { await self?.session.startListening() }
            }
        }
    }

    private func presentStatusItem() {
        statusItem = StatusItemController(session: session) { [weak self] in
            guard let self else { return }
            self.settingsWindow.show(session: self.session, store: self.store, updater: self.updater)
        }
    }
}
