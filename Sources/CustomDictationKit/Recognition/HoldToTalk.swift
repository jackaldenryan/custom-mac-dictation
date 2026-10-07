import AppKit
import CoreGraphics
import Foundation

/// The key held down to talk in hold-to-talk mode.
public struct HoldKey: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt16
    public var name: String

    public init(keyCode: UInt16, name: String) {
        self.keyCode = keyCode
        self.name = name
    }

    public static let rightCommand = HoldKey(keyCode: 54, name: "Right Command ⌘")

    /// Modifier keys offered in the picker (any other key can be recorded).
    public static let presets: [HoldKey] = [
        .rightCommand,
        HoldKey(keyCode: 55, name: "Left Command ⌘"),
        HoldKey(keyCode: 61, name: "Right Option ⌥"),
        HoldKey(keyCode: 58, name: "Left Option ⌥"),
        HoldKey(keyCode: 62, name: "Right Control ⌃"),
        HoldKey(keyCode: 59, name: "Left Control ⌃"),
        HoldKey(keyCode: 60, name: "Right Shift ⇧"),
        HoldKey(keyCode: 56, name: "Left Shift ⇧"),
        HoldKey(keyCode: 63, name: "Fn / Globe"),
    ]

    /// Device-specific flag bit that is set while this modifier key is down
    /// (left and right keys have their own bit). Nil for ordinary keys.
    public static func modifierMask(keyCode: UInt16) -> UInt64? {
        switch keyCode {
        case 59: return 0x0000_0001 // left control
        case 56: return 0x0000_0002 // left shift
        case 60: return 0x0000_0004 // right shift
        case 55: return 0x0000_0008 // left command
        case 54: return 0x0000_0010 // right command
        case 58: return 0x0000_0020 // left option
        case 61: return 0x0000_0040 // right option
        case 62: return 0x0000_2000 // right control
        case 63: return CGEventFlags.maskSecondaryFn.rawValue // fn / globe
        default: return nil
        }
    }

    public var isModifier: Bool { Self.modifierMask(keyCode: keyCode) != nil }

    /// Name for a recorded key.
    public static func named(keyCode: UInt16, characters: String?) -> HoldKey {
        if let preset = presets.first(where: { $0.keyCode == keyCode }) { return preset }
        let special: [UInt16: String] = [
            49: "Space", 36: "Return", 48: "Tab", 53: "Escape", 51: "Delete", 57: "Caps Lock",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
            123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow",
            115: "Home", 119: "End", 116: "Page Up", 121: "Page Down", 117: "Forward Delete",
        ]
        if let name = special[keyCode] { return HoldKey(keyCode: keyCode, name: name) }
        let chars = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return HoldKey(keyCode: keyCode, name: chars.isEmpty ? "Key \(keyCode)" : chars)
    }
}

/// Hold-to-talk: the mic is off until the key is held; what you said is
/// typed when you let go. Saved in settings.json.
public struct HoldToTalkSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var key: HoldKey

    /// New installs start in hold-to-talk mode.
    public static let `default` = HoldToTalkSettings(enabled: true, key: .rightCommand)
    /// Settings saved before this option existed keep listening all the time.
    public static let legacy = HoldToTalkSettings(enabled: false, key: .rightCommand)

    public init(enabled: Bool, key: HoldKey) {
        self.enabled = enabled
        self.key = key
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case key
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        key = try c.decodeIfPresent(HoldKey.self, forKey: .key) ?? .rightCommand
    }
}

/// Turns raw key events into "start talking" / "stop talking". Pure, so it
/// can be tested without a keyboard.
public struct HoldKeyTracker: Sendable {
    public enum Event: Sendable {
        case flagsChanged(keyCode: UInt16, flags: UInt64)
        case keyDown(keyCode: UInt16, isRepeat: Bool)
        case keyUp(keyCode: UInt16)
    }

    public enum Action: Equatable, Sendable {
        case none
        case begin
        /// cancelled: the held modifier was used for a shortcut (⌘Tab),
        /// so what was heard is thrown away.
        case end(cancelled: Bool)
    }

    public struct Outcome: Equatable, Sendable {
        public var action: Action
        /// Keep the key event from reaching apps (ordinary hold keys only;
        /// modifiers always pass through).
        public var swallow: Bool

        public init(action: Action, swallow: Bool) {
            self.action = action
            self.swallow = swallow
        }
    }

    public let key: HoldKey
    public private(set) var isHeld = false
    private var chorded = false

    public init(key: HoldKey) {
        self.key = key
    }

    public mutating func handle(_ event: Event) -> Outcome {
        if let mask = HoldKey.modifierMask(keyCode: key.keyCode) {
            switch event {
            case .flagsChanged(let code, let flags) where code == key.keyCode:
                let down = flags & mask != 0
                if down, !isHeld {
                    isHeld = true
                    chorded = false
                    return Outcome(action: .begin, swallow: false)
                }
                if !down, isHeld {
                    isHeld = false
                    return Outcome(action: .end(cancelled: chorded), swallow: false)
                }
            case .keyDown where isHeld:
                chorded = true
            default:
                break
            }
            return Outcome(action: .none, swallow: false)
        }
        switch event {
        case .keyDown(let code, let isRepeat) where code == key.keyCode:
            if isRepeat || isHeld { return Outcome(action: .none, swallow: true) }
            isHeld = true
            return Outcome(action: .begin, swallow: true)
        case .keyUp(let code) where code == key.keyCode:
            guard isHeld else { return Outcome(action: .none, swallow: true) }
            isHeld = false
            return Outcome(action: .end(cancelled: false), swallow: true)
        default:
            return Outcome(action: .none, swallow: false)
        }
    }
}

/// Watches the keyboard system-wide for the hold key (needs Accessibility).
/// The event tap runs on its own thread so a busy main thread never delays
/// anyone's typing.
public final class HoldKeyMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var tracker: HoldKeyTracker
    private let onAction: @Sendable (HoldKeyTracker.Action) -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    public var key: HoldKey { lock.withLock { tracker.key } }

    public init(key: HoldKey, onAction: @escaping @Sendable (HoldKeyTracker.Action) -> Void) {
        tracker = HoldKeyTracker(key: key)
        self.onAction = onAction
    }

    /// Returns false when the tap can't be created (Accessibility not granted).
    @discardableResult
    public func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HoldKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DiagnosticLog.line("Hold key: could not watch the keyboard (Accessibility not granted?)")
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let thread = Thread { [weak self] in
            guard let self, let tap = self.tap, let source = self.source else { return }
            self.lock.withLock { self.runLoop = CFRunLoopGetCurrent() }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "HoldKeyMonitor"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        DiagnosticLog.line("Hold key: watching \(key.name)")
        return true
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        if let loop = lock.withLock({ runLoop }) {
            CFRunLoopStop(loop)
        }
        thread = nil
    }

    deinit {
        stop()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Our own typing must never count as the hold key.
        if event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) {
            return Unmanaged.passUnretained(event)
        }
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let input: HoldKeyTracker.Event
        switch type {
        case .flagsChanged: input = .flagsChanged(keyCode: code, flags: event.flags.rawValue)
        case .keyDown: input = .keyDown(keyCode: code, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp: input = .keyUp(keyCode: code)
        default: return Unmanaged.passUnretained(event)
        }
        let outcome = lock.withLock { tracker.handle(input) }
        if outcome.action != .none {
            onAction(outcome.action)
        }
        return outcome.swallow ? nil : Unmanaged.passUnretained(event)
    }
}
