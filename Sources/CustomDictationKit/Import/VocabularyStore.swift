import Foundation

public enum VocabularyStore {
    public static func exportJSON(settings: AppSettings, to url: URL) throws {
        let payload = ExportFile(vocabulary: settings.vocabulary, commands: settings.commands)
        let data = try JSONEncoder().encode(payload)
        try data.write(to: url, options: .atomic)
    }

    public static func importJSON(from url: URL) throws -> ExportFile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ExportFile.self, from: data)
    }

    public struct ExportFile: Codable, Sendable {
        public var vocabulary: [VocabEntry]
        public var commands: [CommandSpec]
    }
}
