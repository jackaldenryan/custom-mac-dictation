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

public enum CustomCommandKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case pasteText
    case shortcut
    case openFile

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pasteText: return "Paste text"
        case .shortcut: return "Shortcut"
        case .openFile: return "Open file"
        }
    }
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
    public var vocabulary: [VocabEntry]
    public var commands: [ImportedCommand]
    public var punctuationModes: [String: PunctuationMode]
    public var launchAtLogin: Bool
    public var preferredListeningState: ListeningState
    public var finalizeDelaySeconds: Double
    public var keyRepeatDelaySeconds: Double

    public static let defaultFinalizeDelaySeconds = 0.4
    public static let defaultKeyRepeatDelaySeconds = 0.08

    public static var `default`: AppSettings {
        AppSettings(
            hasCompletedOnboarding: false,
            microphoneUID: nil,
            vocabulary: [],
            commands: [],
            punctuationModes: [:],
            launchAtLogin: true,
            preferredListeningState: .off,
            finalizeDelaySeconds: defaultFinalizeDelaySeconds,
            keyRepeatDelaySeconds: defaultKeyRepeatDelaySeconds
        )
    }

    enum CodingKeys: String, CodingKey {
        case hasCompletedOnboarding
        case microphoneUID
        case vocabulary
        case commands
        case punctuationModes
        case launchAtLogin
        case preferredListeningState
        case finalizeDelaySeconds
        case keyRepeatDelaySeconds
    }

    public init(
        hasCompletedOnboarding: Bool,
        microphoneUID: String?,
        vocabulary: [VocabEntry],
        commands: [ImportedCommand],
        punctuationModes: [String: PunctuationMode],
        launchAtLogin: Bool,
        preferredListeningState: ListeningState,
        finalizeDelaySeconds: Double,
        keyRepeatDelaySeconds: Double
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.microphoneUID = microphoneUID
        self.vocabulary = vocabulary
        self.commands = commands
        self.punctuationModes = punctuationModes
        self.launchAtLogin = launchAtLogin
        self.preferredListeningState = preferredListeningState
        self.finalizeDelaySeconds = Self.clampedFinalizeDelay(finalizeDelaySeconds)
        self.keyRepeatDelaySeconds = Self.clampedKeyRepeatDelay(keyRepeatDelaySeconds)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasCompletedOnboarding = try container.decode(Bool.self, forKey: .hasCompletedOnboarding)
        microphoneUID = try container.decodeIfPresent(String.self, forKey: .microphoneUID)
        vocabulary = try container.decodeIfPresent([VocabEntry].self, forKey: .vocabulary) ?? []
        commands = try container.decodeIfPresent([ImportedCommand].self, forKey: .commands) ?? []
        punctuationModes = try container.decodeIfPresent([String: PunctuationMode].self, forKey: .punctuationModes) ?? [:]
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        preferredListeningState = try container.decodeIfPresent(ListeningState.self, forKey: .preferredListeningState) ?? .off
        finalizeDelaySeconds = Self.clampedFinalizeDelay(
            try container.decodeIfPresent(Double.self, forKey: .finalizeDelaySeconds) ?? Self.defaultFinalizeDelaySeconds
        )
        keyRepeatDelaySeconds = Self.clampedKeyRepeatDelay(
            try container.decodeIfPresent(Double.self, forKey: .keyRepeatDelaySeconds) ?? Self.defaultKeyRepeatDelaySeconds
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encodeIfPresent(microphoneUID, forKey: .microphoneUID)
        try container.encode(vocabulary, forKey: .vocabulary)
        try container.encode(commands, forKey: .commands)
        try container.encode(punctuationModes, forKey: .punctuationModes)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(preferredListeningState, forKey: .preferredListeningState)
        try container.encode(finalizeDelaySeconds, forKey: .finalizeDelaySeconds)
        try container.encode(keyRepeatDelaySeconds, forKey: .keyRepeatDelaySeconds)
    }

    public static func clampedFinalizeDelay(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return defaultFinalizeDelaySeconds }
        return min(max(seconds, 0), 30)
    }

    public static func clampedKeyRepeatDelay(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return defaultKeyRepeatDelaySeconds }
        return min(max(seconds, 0), 2)
    }

    public static func keyRepeatDelayMillis(_ seconds: Double) -> Int? {
        let millis = Int((seconds * 1000).rounded())
        let allowed: Set<Int> = [0, 40, 80, 120, 160, 200, 300, 500]
        return allowed.contains(millis) ? millis : nil
    }

    public static func finalizeDelayTenths(_ seconds: Double) -> Int? {
        let scaled = seconds * 10
        let tenths = Int(scaled.rounded())
        guard (0...20).contains(tenths), abs(scaled - Double(tenths)) < 0.05 else { return nil }
        return tenths
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
