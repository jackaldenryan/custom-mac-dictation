import Foundation

/// Up to three microphones in the order the user prefers them. Listening uses
/// the first one that is plugged in, and falls back to the system default
/// input when none of them are.
public enum MicrophonePriority {
    public static let maxLevels = 3

    /// Drops blank and repeated entries and keeps at most three.
    public static func normalized(_ list: [MicrophoneDevice]) -> [MicrophoneDevice] {
        var seen = Set<String>()
        var out: [MicrophoneDevice] = []
        for mic in list where !mic.uid.isEmpty && seen.insert(mic.uid).inserted {
            out.append(mic)
            if out.count == maxLevels { break }
        }
        return out
    }

    /// The microphone to listen with: the first one in the list that is
    /// available now. Nil means the system default input.
    public static func resolve(_ list: [MicrophoneDevice], available: [MicrophoneDevice]) -> MicrophoneDevice? {
        let present = Set(available.map(\.uid))
        return list.first { present.contains($0.uid) }
    }

    /// Sets slot `index` (0 = first choice) to `mic`, or clears it when nil.
    /// A mic already in another slot swaps places with the slot's old mic;
    /// cleared slots close up.
    public static func setting(_ index: Int, to mic: MicrophoneDevice?, in list: [MicrophoneDevice]) -> [MicrophoneDevice] {
        var slots: [MicrophoneDevice?] = normalized(list).map { $0 }
        guard index >= 0, index < maxLevels else { return normalized(list) }
        while slots.count <= index { slots.append(nil) }
        if let mic, let other = slots.firstIndex(where: { $0?.uid == mic.uid }), other != index {
            slots[other] = slots[index]
        }
        slots[index] = mic
        return normalized(slots.compactMap { $0 })
    }

    /// Makes `mic` the first choice and keeps the others behind it. Nil
    /// clears the list (always use the system default).
    public static func promoting(_ mic: MicrophoneDevice?, in list: [MicrophoneDevice]) -> [MicrophoneDevice] {
        guard let mic else { return [] }
        return normalized([mic] + list.filter { $0.uid != mic.uid })
    }

    /// Older settings saved a single microphone uid.
    public static func migrated(legacyUID: String?) -> [MicrophoneDevice] {
        guard let legacyUID, !legacyUID.isEmpty else { return [] }
        return [MicrophoneDevice(uid: legacyUID, name: "")]
    }

    /// Identifies the input actually in use, so a device change only
    /// restarts capture when it changes what we would listen with. With no
    /// listed mic available, that is whatever the system default is now.
    public static func inputKey(resolved: MicrophoneDevice?, systemDefaultUID: String?) -> String {
        resolved.map { "mic:\($0.uid)" } ?? "default:\(systemDefaultUID ?? "")"
    }
}
