import Foundation

/// The microphone's format as CoreAudio reports it.
public struct DeviceFormat: Equatable, Sendable {
    public var sampleRate: Double
    public var inputChannels: Int
    public var alive: Bool

    public init(sampleRate: Double, inputChannels: Int, alive: Bool) {
        self.sampleRate = sampleRate
        self.inputChannels = inputChannels
        self.alive = alive
    }
}

/// Why this exists: AVAudioEngine silently stops delivering microphone audio
/// when the device's format changes under it. It still reports running and
/// posts no notification (reproduced Oct 7: the built-in mic switched from
/// 48 to 44.1 kHz and buffers stopped until the rate was put back). The app
/// kept "listening" to nothing: after the 0.1.45 relaunch and after a wake
/// it received 0 buffers for 4+ minutes, and mid-session the audio stopped
/// several times, each time until the mic was turned off and on.
public enum CaptureHealth {
    /// A capture started on `started` must be rebuilt when the device now
    /// reports something else (or is gone).
    public static func formatChanged(started: DeviceFormat, now: DeviceFormat) -> Bool {
        !now.alive || now.sampleRate != started.sampleRate || now.inputChannels != started.inputChannels
    }
}

/// Safety net for stalls no notification announces (a dead start after a
/// wake or relaunch). The microphone delivers a buffer every ~0.1 s even in
/// silence (8,699 of 8,701 logged 20-second stretches were on time), so a
/// 2-second gap only happens when the feed is dead.
public struct CaptureWatchdog: Sendable {
    public static let stallSeconds = 2.0
    /// No checks right after a capture starts.
    public static let graceSeconds = 3.0
    /// At most one automatic restart this often.
    public static let minRestartInterval = 10.0
    /// Restarts that bring no audio before giving up.
    public static let maxRestartsWithoutAudio = 3

    public enum Decision: Equatable, Sendable {
        case ok
        case restart(silentFor: Double)
        case giveUp
    }

    private var lastRestart: Double?
    private var restartsWithoutAudio = 0
    public private(set) var gaveUp = false

    public init() {}

    /// - now / captureStartedAt / lastBufferAt: monotonic seconds. Nil
    ///   captureStartedAt means capture is not running (nothing to check).
    public mutating func check(now: Double, captureStartedAt: Double?, lastBufferAt: Double?) -> Decision {
        guard let started = captureStartedAt, !gaveUp else { return .ok }
        if let heard = lastBufferAt, heard >= started, heard > (lastRestart ?? -.infinity) {
            restartsWithoutAudio = 0
        }
        guard now - started >= Self.graceSeconds else { return .ok }
        let lastAudio = max(lastBufferAt ?? started, started)
        let silent = now - lastAudio
        guard silent >= Self.stallSeconds else { return .ok }
        if let last = lastRestart, now - last < Self.minRestartInterval { return .ok }
        if restartsWithoutAudio >= Self.maxRestartsWithoutAudio {
            gaveUp = true
            return .giveUp
        }
        restartsWithoutAudio += 1
        lastRestart = now
        return .restart(silentFor: silent)
    }
}
