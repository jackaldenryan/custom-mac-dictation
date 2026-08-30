import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum Typist {
    public static func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        if !AXIsProcessTrusted() {
            DiagnosticLog.line("Type skipped; Accessibility not granted")
            return
        }
        let units = Array(text.utf16)
        let chunkSize = 20
        var index = 0
        var posted = 0
        while index < units.count {
            let end = min(index + chunkSize, units.count)
            var chunk = Array(units[index..<end])
            postUnicode(&chunk)
            posted += chunk.count
            index = end
        }
        DiagnosticLog.line("Typed \(posted) utf16 into \(frontAppName())")
    }

    public static func press(
        keyCode: UInt16,
        flags: CGEventFlags,
        character: String? = nil,
        times: Int = 1,
        intervalSeconds: Double = AppSettings.defaultKeyRepeatDelaySeconds
    ) {
        if !AXIsProcessTrusted() {
            DiagnosticLog.line("Key skipped; Accessibility not granted")
            return
        }
        let repeats = min(75, max(1, times))
        let gap = AppSettings.clampedKeyRepeatDelay(intervalSeconds)
        let source = CGEventSource(stateID: .privateState)
        source?.localEventsSuppressionInterval = 0
        postModifiers(source: source, flags: flags, keyDown: true)
        for index in 0..<repeats {
            if index > 0, gap > 0 {
                Thread.sleep(forTimeInterval: gap)
            }
            pressKey(keyCode, flags: flags, source: source, character: flags.isEmpty ? character : nil)
        }
        postModifiers(source: source, flags: flags, keyDown: false)
        if flags.contains(.maskShift) {
            clearUnintendedCapsLock()
        }
        DiagnosticLog.line("Pressed key \(keyCode) flags=\(flags.rawValue) into \(frontAppName())")
    }

    public static func deleteSelection() {
        pressKey(51, flags: [])
    }

    public static func deleteBackward(times: Int) {
        guard times > 0 else { return }
        if !AXIsProcessTrusted() { return }
        for _ in 0..<times {
            pressKey(51, flags: [])
        }
    }

    public static func moveRight() {
        pressKey(124, flags: [])
    }

    public static func click(flags: CGEventFlags, right: Bool, times: Int = 1) {
        if !AXIsProcessTrusted() {
            DiagnosticLog.line("Click skipped; Accessibility not granted")
            return
        }
        let repeats = min(75, max(1, times))
        let point = cgMouseLocation()
        let keys = CGEventSource(stateID: .combinedSessionState)
        keys?.localEventsSuppressionInterval = 0
        let button: CGMouseButton = right ? .right : .left
        let downType: CGEventType = right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = right ? .rightMouseUp : .leftMouseUp
        postModifiers(source: keys, flags: flags, keyDown: true)
        if !flags.isEmpty {
            waitForModifierState(flags)
        }
        for index in 1...repeats {
            let down = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: point, mouseButton: button)
            let up = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: point, mouseButton: button)
            down?.flags = flags
            up?.flags = flags
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            if index < repeats {
                Thread.sleep(forTimeInterval: 0.008)
            }
        }
        postModifiers(source: keys, flags: flags, keyDown: false)
        DiagnosticLog.line("Clicked \(right ? "right" : "left") flags=\(flags.rawValue) session=\(CGEventSource.flagsState(.combinedSessionState).rawValue) times=\(repeats) into \(frontAppName())")
    }

    private static func waitForModifierState(_ flags: CGEventFlags) {
        for _ in 0..<25 {
            if CGEventSource.flagsState(.combinedSessionState).contains(flags) { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
        DiagnosticLog.line("Click modifiers not visible in session state flags=\(flags.rawValue) session=\(CGEventSource.flagsState(.combinedSessionState).rawValue)")
    }

    private static func cgMouseLocation() -> CGPoint {
        let loc = NSEvent.mouseLocation
        let maxY = NSScreen.screens.map(\.frame.maxY).max() ?? loc.y
        return CGPoint(x: loc.x, y: maxY - loc.y)
    }

    public static func pressShortcut(keyCode: Int, modifierFlags: UInt64) {
        press(keyCode: UInt16(keyCode), flags: cgFlags(from: modifierFlags))
    }

    public static func cgFlags(from nsModifierFlags: UInt64) -> CGEventFlags {
        let ns = NSEvent.ModifierFlags(rawValue: UInt(nsModifierFlags))
        var flags: CGEventFlags = []
        if ns.contains(.command) { flags.insert(.maskCommand) }
        if ns.contains(.shift) { flags.insert(.maskShift) }
        if ns.contains(.option) { flags.insert(.maskAlternate) }
        if ns.contains(.control) { flags.insert(.maskControl) }
        if ns.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    private static let modifierKeys: [(CGEventFlags, UInt16)] = [
        (.maskCommand, 55),
        (.maskControl, 59),
        (.maskAlternate, 58),
        (.maskShift, 56),
        (.maskSecondaryFn, 63),
    ]

    private static func pressKey(
        _ keyCode: UInt16,
        flags: CGEventFlags,
        source: CGEventSource? = nil,
        character: String? = nil
    ) {
        let eventSource = source ?? CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        if let character, var buffer = Optional(Array(character.utf16)) {
            down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            up?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func postModifiers(source: CGEventSource?, flags: CGEventFlags, keyDown: Bool) {
        let keys = keyDown ? modifierKeys : modifierKeys.reversed()
        var held: CGEventFlags = []
        for (flag, code) in keys where flags.contains(flag) {
            if keyDown { held.insert(flag) }
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown)
            event?.flags = keyDown ? held : held.subtracting(flag)
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func clearUnintendedCapsLock() {
        let state = CGEventSource.flagsState(.hidSystemState)
        guard state.contains(.maskAlphaShift) else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 57, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 57, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        DiagnosticLog.line("Cleared unintended caps lock")
    }

    private static func postUnicode(_ buffer: inout [UniChar]) {
        let source = CGEventSource(stateID: .privateState)
        source?.localEventsSuppressionInterval = 0
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
        up?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func frontAppName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
    }
}
