import AppKit
import Darwin
import Foundation

public enum ConfigFolder {
    public static var folderName: String { AppRuntime.configFolderName }
    public static let didChange = Notification.Name("CustomDictation.configDidChange")

    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment["CUSTOM_DICTATION_CONFIG"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(folderName, isDirectory: true)
    }

    public static var commandsDirectory: URL {
        root.appendingPathComponent("commands", isDirectory: true)
    }

    public static var vocabularyDirectory: URL {
        root.appendingPathComponent("vocabulary", isDirectory: true)
    }

    public static var delaysURL: URL {
        root.appendingPathComponent("delays.json")
    }

    public static var postProcessURL: URL {
        root.appendingPathComponent("post-process.json")
    }

    public static var prefsURL: URL {
        root.appendingPathComponent("settings.json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    nonisolated(unsafe) private static var watchers: [DispatchSourceFileSystemObject] = []
    nonisolated(unsafe) private static var ignoreWatcherUntil = Date.distantPast

    public static func ensureLayout() {
        let fm = FileManager.default
        try? fm.createDirectory(at: commandsDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: vocabularyDirectory, withIntermediateDirectories: true)
        let readme = root.appendingPathComponent("README.md")
        try? readmeText.data(using: .utf8)?.write(to: readme, options: .atomic)
        seedMissingBuiltins()
    }

    public static func seedMissingBuiltins() {
        for spec in CommandSpec.builtIns {
            let url = commandsDirectory.appendingPathComponent(fileName(for: spec.id))
            if !FileManager.default.fileExists(atPath: url.path) {
                try? writeJSON(spec, to: url)
            }
        }
    }

    public static func restoreBuiltins() {
        ignoreWatcherUntil = Date().addingTimeInterval(0.4)
        for spec in CommandSpec.builtIns {
            let url = commandsDirectory.appendingPathComponent(fileName(for: spec.id))
            try? writeJSON(spec, to: url)
        }
    }

    public static func loadCommands() -> [CommandSpec] {
        let files = jsonFiles(in: commandsDirectory)
        var loaded: [CommandSpec] = []
        for url in files {
            guard let spec = try? JSONDecoder().decode(CommandSpec.self, from: Data(contentsOf: url)) else { continue }
            loaded.append(spec)
        }
        return loaded.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }

    public static func loadVocabulary() -> [VocabEntry] {
        let files = jsonFiles(in: vocabularyDirectory)
        var loaded: [VocabEntry] = []
        for url in files {
            guard let entry = try? JSONDecoder().decode(VocabEntry.self, from: Data(contentsOf: url)) else { continue }
            loaded.append(entry)
        }
        return loaded.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
    }

    public static func writeCommands(_ commands: [CommandSpec]) {
        ignoreWatcherUntil = Date().addingTimeInterval(0.4)
        let fm = FileManager.default
        let wanted = Set(commands.map { fileName(for: $0.id) })
        for url in jsonFiles(in: commandsDirectory) {
            if !wanted.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        }
        for spec in commands {
            let url = commandsDirectory.appendingPathComponent(fileName(for: spec.id))
            try? writeJSON(spec, to: url)
        }
    }

    public static func writeVocabulary(_ vocabulary: [VocabEntry]) {
        ignoreWatcherUntil = Date().addingTimeInterval(0.4)
        let fm = FileManager.default
        let wanted = Set(vocabulary.map { fileName(for: $0.id) })
        for url in jsonFiles(in: vocabularyDirectory) {
            if !wanted.contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        }
        for entry in vocabulary {
            let url = vocabularyDirectory.appendingPathComponent(fileName(for: entry.id))
            try? writeJSON(entry, to: url)
        }
    }

    public static func migrateIfNeeded(settings: AppSettings) {
        let userFiles = jsonFiles(in: commandsDirectory).filter { !$0.lastPathComponent.hasPrefix("builtin.") }
        if userFiles.isEmpty {
            let extras = settings.commands.filter { !$0.builtin }
            if !extras.isEmpty { writeCommands(extras) }
        }
        if jsonFiles(in: vocabularyDirectory).isEmpty, !settings.vocabulary.isEmpty {
            writeVocabulary(settings.vocabulary)
        }
        if !FileManager.default.fileExists(atPath: delaysURL.path) {
            writeDelays(DelaySettings(settings))
        }
        if !FileManager.default.fileExists(atPath: postProcessURL.path) {
            writePostProcess(activeID: settings.activePostProcessID, configs: settings.postProcessConfigs)
        }
        if !FileManager.default.fileExists(atPath: prefsURL.path) {
            writePrefs(PrefsSettings(settings))
        }
    }

    public static func loadDelays() -> DelaySettings? {
        guard let data = try? Data(contentsOf: delaysURL) else { return nil }
        return try? JSONDecoder().decode(DelaySettings.self, from: data)
    }

    public static func writeDelays(_ delays: DelaySettings) {
        ignoreWatcherUntil = Date().addingTimeInterval(0.4)
        try? writeJSON(delays, to: delaysURL)
    }

    public static func loadPostProcess() -> (activeID: String, configs: [PostProcessConfig])? {
        guard let data = try? Data(contentsOf: postProcessURL),
              let file = try? JSONDecoder().decode(PostProcessFile.self, from: data)
        else { return nil }
        return (file.activeID, file.configs)
    }

    public static func writePostProcess(activeID: String, configs: [PostProcessConfig]) {
        ignoreWatcherUntil = Date().addingTimeInterval(0.4)
        try? writeJSON(PostProcessFile(activeID: activeID, configs: configs), to: postProcessURL)
    }

    public static func loadPrefs() -> PrefsSettings? {
        guard let data = try? Data(contentsOf: prefsURL) else { return nil }
        return try? JSONDecoder().decode(PrefsSettings.self, from: data)
    }

    public static func writePrefs(_ prefs: PrefsSettings) {
        ignoreWatcherUntil = Date().addingTimeInterval(0.4)
        try? writeJSON(prefs, to: prefsURL)
    }

    public static func export(to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: root, to: destination)
    }

    public static func importReplacing(from source: URL) throws {
        ignoreWatcherUntil = Date().addingTimeInterval(0.8)
        let fm = FileManager.default
        if fm.fileExists(atPath: root.path) {
            try fm.removeItem(at: root)
        }
        try fm.copyItem(at: source, to: root)
        ensureLayout()
        notify()
    }

    public static func startWatching() {
        stopWatching()
        watch(root)
        watch(commandsDirectory)
        watch(vocabularyDirectory)
    }

    public static func stopWatching() {
        watchers.forEach { $0.cancel() }
        watchers = []
    }

    public static func revealInFinder() {
        ensureLayout()
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    public static func fileName(for id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = id.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        var name = String(scalars)
        while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
        if name.isEmpty { name = "item" }
        if name.hasSuffix(".json") { return name }
        return name + ".json"
    }

    private static func watch(_ directory: URL) {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler {
            guard Date() >= ignoreWatcherUntil else { return }
            notify()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        watchers.append(source)
    }

    private static func notify() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static func jsonFiles(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?.filter {
            $0.pathExtension.lowercased() == "json"
        } ?? []
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static let readmeText = """
    # Custom Dictation config

    This folder is the source of truth for commands, vocabulary, delays, post-process, and other settings.

     Path: `~/.custom-dictation-config` (local test builds use `~/.custom-dictation-config-local`)

    Edit files here (or have an agent edit them). The app reloads on change. Import in the app replaces this folder. Export copies it.

    ## delays.json

    All pause/delay times, in seconds.

    ```json
    {
      "finalizeDelaySeconds": 0.4,
      "keyRepeatDelaySeconds": 0.08,
      "lonePunctuationDelaySeconds": 1.0
    }
    ```

    ## post-process.json

    Named JavaScript configs. `function process(ctx)` returns the string to type, or null to ignore.

    ```json
    {
      "activeID": "default",
      "configs": [
        {
          "id": "default",
          "name": "Default",
          "script": "function process(ctx) { return ctx.text; }"
        }
      ]
    }
    ```

    ## settings.json

    Microphone, login, onboarding, and punctuation mode.

    ## commands/

    One JSON file per command.

    ```json
    {
      "id": "custom.hello",
      "enabled": true,
      "builtin": false,
      "phrases": ["say hello"],
      "match": "exact",
      "when": "listening",
      "priority": 100,
      "action": "pasteText",
      "pasteText": "hello"
    }
    ```

     `match`: `exact` | `prefix` | `keyPressGrammar` | `appSlot`  
     `when`: `always` (start/stop) | `listening`  
     `action`: `startListening` `stopListening` `keyPressGrammar` `openApp` `quitApp` `quitFrontmost` `capitalize` `uppercase` `lowercase` `pasteText` `shortcut` `openFile` `click`

     Put `{app}` in a phrase with `match` `appSlot` and action `openApp` or `quitApp`. Example: `"open {app}"`.

     For `click`, set `clickButton` to `left` or `right`, `clickTimes` (1, 2, or 3), and `modifierFlags` (same numbers as shortcuts). Example phrases: `command click`.

     Lower `priority` runs first among the same stage. User `exact` commands (priority 100) still beat press/open/quit.

     Shipped defaults are `builtin.*.json`. Edit phrases, disable, or delete them. Restore built-ins in the app puts the shipped files back.

    ## vocabulary/

    One JSON file per word.

    ```json
    {
      "word": "Zep",
      "ipa": [],
      "locale": "en_US",
      "enabled": true
    }
    ```

    Restart listening after vocabulary changes.
    """
}

public struct DelaySettings: Codable, Equatable, Sendable {
    public var finalizeDelaySeconds: Double
    public var keyRepeatDelaySeconds: Double
    public var lonePunctuationDelaySeconds: Double

    public init(finalizeDelaySeconds: Double, keyRepeatDelaySeconds: Double, lonePunctuationDelaySeconds: Double) {
        self.finalizeDelaySeconds = AppSettings.clampedFinalizeDelay(finalizeDelaySeconds)
        self.keyRepeatDelaySeconds = AppSettings.clampedKeyRepeatDelay(keyRepeatDelaySeconds)
        self.lonePunctuationDelaySeconds = AppSettings.clampedLonePunctuationDelay(lonePunctuationDelaySeconds)
    }

    public init(_ settings: AppSettings) {
        self.init(
            finalizeDelaySeconds: settings.finalizeDelaySeconds,
            keyRepeatDelaySeconds: settings.keyRepeatDelaySeconds,
            lonePunctuationDelaySeconds: settings.lonePunctuationDelaySeconds
        )
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        finalizeDelaySeconds = AppSettings.clampedFinalizeDelay(
            try c.decodeIfPresent(Double.self, forKey: .finalizeDelaySeconds) ?? AppSettings.defaultFinalizeDelaySeconds
        )
        keyRepeatDelaySeconds = AppSettings.clampedKeyRepeatDelay(
            try c.decodeIfPresent(Double.self, forKey: .keyRepeatDelaySeconds) ?? AppSettings.defaultKeyRepeatDelaySeconds
        )
        lonePunctuationDelaySeconds = AppSettings.clampedLonePunctuationDelay(
            try c.decodeIfPresent(Double.self, forKey: .lonePunctuationDelaySeconds) ?? AppSettings.defaultLonePunctuationDelaySeconds
        )
    }
}

public struct PrefsSettings: Codable, Equatable, Sendable {
    public var hasCompletedOnboarding: Bool
    public var microphoneUID: String?
    public var punctuationModes: [String: PunctuationMode]
    public var launchAtLogin: Bool
    public var preferredListeningState: ListeningState

    public init(_ settings: AppSettings) {
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        microphoneUID = settings.microphoneUID
        punctuationModes = settings.punctuationModes
        launchAtLogin = settings.launchAtLogin
        preferredListeningState = settings.preferredListeningState
    }
}

struct PostProcessFile: Codable, Equatable, Sendable {
    var activeID: String
    var configs: [PostProcessConfig]
}
