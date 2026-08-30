import Foundation

public enum AppRuntime {
    public static let isLocalTest: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["CUSTOM_DICTATION_DEV"] == "1" { return true }
        if let path = env["CUSTOM_DICTATION_CONFIG"], !path.isEmpty { return true }
        return Bundle.main.bundleIdentifier?.hasSuffix(".local") == true
    }()

    public static var displayName: String {
        isLocalTest ? "Custom Dictation (local)" : "Custom Dictation"
    }

    public static var configFolderName: String {
        isLocalTest ? ".custom-dictation-config-local" : ".custom-dictation-config"
    }
}
