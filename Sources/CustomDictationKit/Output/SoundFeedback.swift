import AppKit

public enum SoundFeedback {
    nonisolated(unsafe) public static var isEnabled = true

    public static func playStart() {
        play("Pop")
    }

    public static func playStop() {
        play("Tink")
    }

    public static func playCommand() {
        play("Morse")
    }

    private static func play(_ name: String) {
        guard isEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
