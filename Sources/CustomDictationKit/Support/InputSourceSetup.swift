import AppKit
import Carbon
import Foundation

public struct InputSourceState: Equatable, Sendable {
    public var installed: Bool
    public var enabled: Bool
    public var selected: Bool

    public init(installed: Bool, enabled: Bool, selected: Bool) {
        self.installed = installed
        self.enabled = enabled
        self.selected = selected
    }

    public var isReady: Bool { installed && enabled && selected }
}

public enum InputSourceSetup {
    public static func shouldPrompt(_ state: InputSourceState) -> Bool {
        !state.isReady
    }

    public static func status() -> InputSourceState {
        let sources = ours()
        guard !sources.isEmpty else {
            return InputSourceState(installed: false, enabled: false, selected: false)
        }
        let enabled = sources.contains { boolProp($0, kTISPropertyInputSourceIsEnabled) }
        let selected = sources.contains { boolProp($0, kTISPropertyInputSourceIsSelected) }
        return InputSourceState(installed: true, enabled: enabled, selected: selected)
    }

    public static func inputMethodsURL(appName: String, home: URL) -> URL {
        home.appendingPathComponent("Library/Input Methods/\(appName).app", isDirectory: true)
    }

    @discardableResult
    public static func installBundle() -> Bool {
        guard let src = Bundle.main.bundleURL as URL? else { return false }
        let name = (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Custom Dictation"
        let dest = inputMethodsURL(appName: name, home: FileManager.default.homeDirectoryForCurrentUser)
        if src.standardizedFileURL == dest.standardizedFileURL { return true }
        do {
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
            let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            _ = try? Process.run(URL(fileURLWithPath: lsregister), arguments: ["-f", dest.path])
            DiagnosticLog.line("Installed input method at \(dest.path)")
            return true
        } catch {
            DiagnosticLog.line("Input method install failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    public static func ensure() -> Bool {
        _ = installBundle()
        for source in ours() {
            TISEnableInputSource(source)
            TISSelectInputSource(source)
        }
        return status().isReady
    }

    public static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources",
            "x-apple.systempreferences:com.apple.preference.keyboard",
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }

    private static func ours() -> [TISInputSource] {
        guard let cf = TISCreateInputSourceList(nil, true)?.takeRetainedValue() else { return [] }
        let bundle = Bundle.main.bundleIdentifier ?? ""
        guard !bundle.isEmpty else { return [] }
        return (cf as! [TISInputSource]).filter { isOurs($0, bundle: bundle) }
    }

    private static func isOurs(_ source: TISInputSource, bundle: String) -> Bool {
        if let id = stringProp(source, kTISPropertyBundleID), id == bundle { return true }
        if let id = stringProp(source, kTISPropertyInputSourceID), id == bundle || id.hasPrefix(bundle + ".") {
            return true
        }
        return false
    }

    private static func stringProp(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? String
    }

    private static func boolProp(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, key) else { return false }
        let value = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }
}
