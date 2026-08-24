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

    public static func press(keyCode: UInt16, flags: CGEventFlags, character: String? = nil) {
        if !AXIsProcessTrusted() {
            DiagnosticLog.line("Key skipped; Accessibility not granted")
            return
        }
        let source = CGEventSource(stateID: .privateState)
        source?.localEventsSuppressionInterval = 0
        postModifiers(source: source, flags: flags, keyDown: true)

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        if flags.isEmpty, let character, var buffer = Optional(Array(character.utf16)) {
            down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            up?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        postModifiers(source: source, flags: flags, keyDown: false)
        if flags.contains(.maskShift) {
            clearUnintendedCapsLock()
        }
        DiagnosticLog.line("Pressed key \(keyCode) flags=\(flags.rawValue) into \(frontAppName())")
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

    private static func postModifiers(source: CGEventSource?, flags: CGEventFlags, keyDown: Bool) {
        let keys = keyDown ? modifierKeys : modifierKeys.reversed()
        for (flag, code) in keys where flags.contains(flag) {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: keyDown)
            event?.flags = keyDown ? flag : []
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
