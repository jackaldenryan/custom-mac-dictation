import AppKit
import Foundation

public enum AppControlError: Error {
    case notFound
}

public enum AppController {
    public static func open(spokenName: String) throws {
        guard let app = AppNameResolver.resolve(spokenName) else { throw AppControlError.notFound }
        if let running = app.running {
            running.activate()
        } else {
            NSWorkspace.shared.open(app.url)
        }
    }

    public static func quit(spokenName: String) throws {
        guard let app = AppNameResolver.resolve(spokenName) else { throw AppControlError.notFound }
        if let running = app.running {
            running.terminate()
        } else {
            throw AppControlError.notFound
        }
    }
}
