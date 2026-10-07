import AppKit

/// Things the app makes a sound for. Each one's sound is a setting.
public enum SoundEvent: String, CaseIterable, Codable, Sendable, Identifiable {
    case startListening
    case stopListening
    case commandRan
    case commandFailed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .startListening: return "Start listening"
        case .stopListening: return "Stop listening"
        case .commandRan: return "Command ran"
        case .commandFailed: return "Command failed"
        }
    }

    /// "" means no sound.
    public var defaultSound: String {
        switch self {
        case .startListening: return "Blow"
        case .stopListening: return "Bottle"
        case .commandRan: return "Purr"
        case .commandFailed: return "Basso"
        }
    }
}

/// Which sound plays for each event, and whether failures are spoken.
/// Saved in settings.json.
public struct SoundSettings: Codable, Equatable, Sendable {
    /// Event raw value → system sound name ("" = none).
    public var sounds: [String: String]
    /// Say failures out loud ("I could not find Zoom").
    public var speakFailures: Bool

    public static let `default` = SoundSettings(sounds: [:], speakFailures: true)
    /// What the spoken-failure Test button says.
    public static let sampleFailure = "I could not find Zoom"

    public init(sounds: [String: String] = [:], speakFailures: Bool = true) {
        self.sounds = sounds
        self.speakFailures = speakFailures
    }

    public subscript(event: SoundEvent) -> String {
        get { sounds[event.rawValue] ?? event.defaultSound }
        set { sounds[event.rawValue] = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case sounds
        case speakFailures
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sounds = try c.decodeIfPresent([String: String].self, forKey: .sounds) ?? [:]
        speakFailures = try c.decodeIfPresent(Bool.self, forKey: .speakFailures) ?? true
    }
}

public enum SoundFeedback {
    /// Off in tests.
    nonisolated(unsafe) public static var isEnabled = true

    /// macOS alert sounds (System Settings → Sound), plus any in
    /// ~/Library/Sounds.
    public static func availableSounds() -> [String] {
        let dirs = [
            URL(fileURLWithPath: "/System/Library/Sounds"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds"),
        ]
        var names = Set<String>()
        for dir in dirs {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for file in files where ["aiff", "aif", "caf", "wav", "m4a", "mp3"].contains((file as NSString).pathExtension.lowercased()) {
                names.insert((file as NSString).deletingPathExtension)
            }
        }
        if names.isEmpty {
            names = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]
        }
        return names.sorted()
    }

    public static func play(_ event: SoundEvent, settings: SoundSettings) {
        play(named: settings[event])
    }

    /// The Test button: plays a sound now ("" plays nothing).
    public static func play(named name: String) {
        guard isEnabled, !name.isEmpty else { return }
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.stop()
        sound.play()
    }
}
