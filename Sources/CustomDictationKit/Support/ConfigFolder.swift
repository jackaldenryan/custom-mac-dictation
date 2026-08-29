import AppKit
import Darwin
import Foundation

public enum ConfigFolder {
    public static let folderName = ".custom-dictation-config"
    public static let didChange = Notification.Name("CustomDictation.configDidChange")

    public static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(folderName, isDirectory: true)
    }

    public static var commandsDirectory: URL {
        root.appendingPathComponent("commands", isDirectory: true)
    }

    public static var vocabularyDirectory: URL {
        root.appendingPathComponent("vocabulary", isDirectory: true)
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
        if !fm.fileExists(atPath: readme.path) {
            try? readmeText.data(using: .utf8)?.write(to: readme, options: .atomic)
        }
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
        let wanted = Set(commands.filter { !$0.builtin }.map { fileName(for: $0.id) })
        for url in jsonFiles(in: commandsDirectory) {
            let name = url.lastPathComponent
            if name.hasPrefix("builtin.") { continue }
            if !wanted.contains(name) {
                try? fm.removeItem(at: url)
            }
        }
        for spec in commands where !spec.builtin {
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

    public static func migrateIfNeeded(commands: [CommandSpec], vocabulary: [VocabEntry]) {
        let userFiles = jsonFiles(in: commandsDirectory).filter { !$0.lastPathComponent.hasPrefix("builtin.") }
        if userFiles.isEmpty {
            let extras = commands.filter { !$0.builtin }
            if !extras.isEmpty { writeCommands(extras) }
        }
        if jsonFiles(in: vocabularyDirectory).isEmpty, !vocabulary.isEmpty {
            writeVocabulary(vocabulary)
        }
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

    This folder is the source of truth for commands and vocabulary.

    Path: `~/.custom-dictation-config`

    Edit files here (or have an agent edit them). The app reloads on change. Import in the app replaces this folder. Export copies it.

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

    `match`: `exact` | `prefix` | `keyPressGrammar`  
    `when`: `always` (start/stop) | `listening`  
    `action`: `startListening` `stopListening` `keyPressGrammar` `openApp` `quitApp` `quitFrontmost` `capitalize` `uppercase` `lowercase` `pasteText` `shortcut` `openFile`

    Lower `priority` runs first among the same stage. User `exact` commands (priority 100) still beat built-in press/open/quit, matching the previous app.

    Built-in files are `builtin.*.json`. Delete or edit them to change those behaviors. Use Restore built-in commands in the app to put them back.

    ## vocabulary/

    One JSON file per word.

    ```json
    {
      "word": "Zep",
      "ipa": [],
      "locale": "en_US"
    }
    ```

    Restart listening after vocabulary changes.
    """
}
