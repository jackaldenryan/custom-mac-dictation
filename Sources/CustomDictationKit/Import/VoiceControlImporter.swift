import Foundation

public struct VoiceControlImportResult: Sendable {
    public var vocabulary: [VocabEntry]
    public var commands: [ImportedCommand]
}

public enum VoiceControlImporter {
    public static let vocabularyPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/com.apple.SpeechRecognitionCore.Vocabulary.plist")
    public static let commandsDomain = "com.apple.speech.recognition.AppleSpeechRecognition.CustomCommands"
    public static let systemWideScope = "com.apple.speech.SystemWideScope"

    public static func importFromThisMac() throws -> VoiceControlImportResult {
        let vocab = try loadVocabulary()
        let commands = try loadCommands()
        return VoiceControlImportResult(vocabulary: vocab, commands: commands)
    }

    public static func loadVocabulary(from url: URL = vocabularyPath) throws -> [VocabEntry] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let root = plist as? [String: Any],
              let entries = root["CACVocabularyEntries"] as? [[String: Any]]
        else { return [] }
        return entries.compactMap { entry in
            guard let word = entry["Text"] as? String, !word.isEmpty else { return nil }
            return VocabEntry(
                word: word,
                ipa: entry["TextIPAs"] as? [String] ?? [],
                locale: entry["LocaleIdentifier"] as? String ?? "en_US"
            )
        }
    }

    public static func loadCommands() throws -> [ImportedCommand] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["export", commandsDomain, "-"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return [] }
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let root = plist as? [String: Any] else { return [] }

        var imported: [ImportedCommand] = []
        for (key, value) in root {
            guard key.hasPrefix("Custom."), let dict = value as? [String: Any] else { continue }
            guard let type = dict["CustomType"] as? String else { continue }
            let phrases = phrases(from: dict["CustomCommands"])
            guard !phrases.isEmpty else { continue }
            let scope = dict["CustomScope"] as? String
            let scopeBundle = (scope == systemWideScope) ? nil : scope
            let enabled = (dict["Enabled"] as? Bool) ?? true
            switch type {
            case "Shortcut":
                imported.append(ImportedCommand(
                    id: key,
                    phrases: phrases,
                    kind: .shortcut,
                    enabled: enabled,
                    scopeBundleID: scopeBundle,
                    keyCode: intValue(dict["CustomShortcutKeyCode"]),
                    modifierFlags: uintValue(dict["CustomShortcutModifierFlags"])
                ))
            case "PasteText":
                imported.append(ImportedCommand(
                    id: key,
                    phrases: phrases,
                    kind: .pasteText,
                    enabled: enabled,
                    scopeBundleID: scopeBundle,
                    pasteText: pastePlainText(dict["CustomPasteText"])
                ))
            case "File":
                imported.append(ImportedCommand(
                    id: key,
                    phrases: phrases,
                    kind: .openFile,
                    enabled: enabled,
                    scopeBundleID: scopeBundle,
                    fileBookmark: firstBookmark(dict["CustomBookmarkList"]),
                    filePath: firstString(dict["CustomFileNameList"])
                ))
            default:
                continue
            }
        }
        return imported.sorted { $0.id < $1.id }
    }

    private static func phrases(from value: Any?) -> [String] {
        guard let dict = value as? [String: Any] else { return [] }
        return dict.values.flatMap { item -> [String] in
            if let list = item as? [String] { return list }
            return []
        }.filter { !$0.isEmpty }
    }

    private static func pastePlainText(_ value: Any?) -> String? {
        guard let items = value as? [[String: Any]] else { return nil }
        if let plain = items.first(where: { ($0["CustomPasteBoardType"] as? String) == "public.utf8-plain-text" }) {
            if let text = plain["CustomPasteBoardData"] as? String { return text }
            if let data = plain["CustomPasteBoardData"] as? Data { return String(data: data, encoding: .utf8) }
        }
        if let any = items.first {
            if let text = any["CustomPasteBoardData"] as? String { return text }
            if let data = any["CustomPasteBoardData"] as? Data { return String(data: data, encoding: .utf8) }
        }
        return nil
    }

    private static func firstBookmark(_ value: Any?) -> Data? {
        if let data = value as? Data { return data }
        if let list = value as? [Data] { return list.first }
        if let list = value as? [Any] { return list.first as? Data }
        return nil
    }

    private static func firstString(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let list = value as? [String] { return list.first }
        if let list = value as? [Any] { return list.first as? String }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func uintValue(_ value: Any?) -> UInt64? {
        if let number = value as? UInt64 { return number }
        if let number = value as? Int { return UInt64(number) }
        if let number = value as? NSNumber { return number.uint64Value }
        return nil
    }
}
