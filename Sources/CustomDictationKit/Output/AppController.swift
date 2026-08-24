import AppKit
import Foundation

public enum AppControlError: Error {
    case notFound
}

public enum AppController {
    public static func open(spokenName: String) throws {
        guard let app = AppNameResolver.resolve(spokenName) else { throw AppControlError.notFound }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, error in
            if let error {
                DiagnosticLog.line("Open failed: \(error.localizedDescription)")
            }
        }
    }

    public static func quit(spokenName: String) throws {
        guard let app = AppNameResolver.resolve(spokenName) else { throw AppControlError.notFound }
        guard let running = AppNameResolver.runningApp(bundleIdentifier: app.bundleIdentifier, url: app.url) else {
            throw AppControlError.notFound
        }
        running.terminate()
    }
}
