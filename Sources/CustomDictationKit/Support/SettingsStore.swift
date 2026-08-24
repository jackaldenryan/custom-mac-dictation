import Foundation

public enum PunctuationMode: String, Codable, CaseIterable, Sendable {
    case character
    case word
    case off
}

public struct VocabEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String { word.lowercased() }
    public var word: String
    public var ipa: [String]
    public var locale: String

    public init(word: String, ipa: [String] = [], locale: String = "en_US") {
        self.word = word
        self.ipa = ipa
        self.locale = locale
    }
}

public enum CustomCommandKind: String, Codable, Sendable {
    case shortcut
    case pasteText
    case openFile
}

public struct ImportedCommand: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var phrases: [String]
    public var kind: CustomCommandKind
    public var enabled: Bool
    public var scopeBundleID: String?
    public var keyCode: Int?
    public var modifierFlags: UInt64?
    public var pasteText: String?
    public var fileBookmark: Data?
    public var filePath: String?

    public init(
        id: String,
        phrases: [String],
        kind: CustomCommandKind,
        enabled: Bool = true,
        scopeBundleID: String? = nil,
        keyCode: Int? = nil,
        modifierFlags: UInt64? = nil,
        pasteText: String? = nil,
        fileBookmark: Data? = nil,
        filePath: String? = nil
    ) {
        self.id = id
        self.phrases = phrases
        self.kind = kind
        self.enabled = enabled
        self.scopeBundleID = scopeBundleID
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.pasteText = pasteText
        self.fileBookmark = fileBookmark
        self.filePath = filePath
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var hasCompletedOnboarding: Bool
    public var microphoneUID: String?
    public var neverQuitNames: [String]
    public var vocabulary: [VocabEntry]
    public var commands: [ImportedCommand]
    public var punctuationModes: [String: PunctuationMode]
    public var launchAtLogin: Bool

    public static let defaultNeverQuit = ["Zoom", "Terminal"]

    public static var `default`: AppSettings {
        AppSettings(
            hasCompletedOnboarding: false,
            microphoneUID: nil,
            neverQuitNames: defaultNeverQuit,
            vocabulary: [],
            commands: [],
            punctuationModes: [:],
            launchAtLogin: true
        )
    }
}

public final class SettingsStore: @unchecked Sendable {
    public static let shared = SettingsStore()

    private let url: URL
    private let queue = DispatchQueue(label: "com.jackaldenryan.custom-mac-dictation.settings")
    private var cached: AppSettings

    public init(url: URL? = nil) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CustomDictation", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.url = url ?? folder.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: self.url),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            cached = decoded
        } else {
            cached = .default
        }
    }

    public var settings: AppSettings {
        queue.sync { cached }
    }

    @discardableResult
    public func update(_ mutate: (inout AppSettings) -> Void) -> AppSettings {
        queue.sync {
            mutate(&cached)
            if let data = try? JSONEncoder().encode(cached) {
                try? data.write(to: url, options: .atomic)
            }
            return cached
        }
    }
}
