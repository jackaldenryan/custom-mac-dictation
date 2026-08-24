import AppKit
import CoreGraphics
import Foundation

public enum Typist {
    public static func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        var buffer = Array(text.utf16)
        let length = buffer.count
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        down?.keyboardSetUnicodeString(stringLength: length, unicodeString: &buffer)
        up?.keyboardSetUnicodeString(stringLength: length, unicodeString: &buffer)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    public static func press(keyCode: UInt16, flags: CGEventFlags, character: String? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        if let character, var buffer = Optional(Array(character.utf16)) {
            down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            up?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
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
        if ns.contains(.capsLock) { flags.insert(.maskAlphaShift) }
        return flags
    }
}
