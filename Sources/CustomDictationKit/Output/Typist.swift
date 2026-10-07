import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum Typist {
    /// - checkFocus: skip keystrokes when the focus takes no text (they would
    ///   beep, see KeystrokePolicy). LivePhrase checks once per phrase itself.
    public static func typeText(_ text: String, preferAX: Bool = true, checkFocus: Bool = true) {
        guard !text.isEmpty else { return }
        if !AXIsProcessTrusted() {
            DiagnosticLog.line("Type skipped; Accessibility not granted")
            return
        }
        if FieldEditor.focusedLooksLikeStub() {
            DiagnosticLog.line("Type skipped; focused field is a stub")
            return
        }
        if preferAX, FieldEditor.insert(text) {
            DiagnosticLog.line("AX inserted \(text.utf16.count) utf16 into \(frontAppName())")
            return
        }
        if checkFocus {
            let target = FieldEditor.focusedTakesKeystrokes()
            guard target.allowed else {
                DiagnosticLog.line("Type skipped; focus in \(target.app) is \(target.role), not a text field (keystrokes would beep)")
                return
            }
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
        intervalSeconds: Double = AppSettings.defaultKeyRepeatDelaySeconds,
        hidSystem: Bool = false
    ) {
        if !AXIsProcessTrusted() {
            DiagnosticLog.line("Key skipped; Accessibility not granted")
            return
        }
        let repeats = min(75, max(1, times))
        let gap = AppSettings.clampedKeyRepeatDelay(intervalSeconds)
        let source = CGEventSource(stateID: hidSystem ? .hidSystemState : .privateState)
        source?.localEventsSuppressionInterval = 0
        postModifiers(source: source, flags: flags, keyDown: true)
        for index in 0..<repeats {
            if index > 0, gap > 0 {
                Thread.sleep(forTimeInterval: gap)
            }
            pressKey(keyCode, flags: flags, source: source, character: flags.isEmpty ? character : nil)
        }
        postModifiers(source: source, flags: flags, keyDown: false)
        releaseModifiers()
        if flags.contains(.maskShift) {
            clearUnintendedCapsLock()
        }
        DiagnosticLog.line("Pressed key \(keyCode) flags=\(flags.rawValue) into \(frontAppName())")
    }

    public static func deleteSelection() {
        pressKey(51, flags: [])
    }

    public static func releaseModifiers() {
        let source = CGEventSource(stateID: .hidSystemState)
        for code: UInt16 in [56, 60, 55, 54, 58, 61, 59, 62, 63] {
            let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
            up?.flags = []
            up?.post(tap: .cghidEventTap)
        }
    }

    /// times is a CHARACTER count: one backspace deletes a full grapheme, so
    /// callers must pass character counts, not UTF-16 lengths (emoji would
    /// otherwise over-delete).
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
        if flags == .maskCommand, !right, repeats == 1, LinkOpener.openLinkUnderPointerInNewTab(at: cgMouseLocation()) {
            return
        }
        if flags.isEmpty, !right, FieldEditor.pressAtMouse(times: repeats) {
            return
        }
        // Modifier clicks ("shift click", "command click", "option click")
        // must be real mouse events with the modifier held. The old path
        // asked System Events to `click at` with `key down shift`, but that
        // click is an Accessibility press on the element, not a mouse event,
        // so the app never saw Shift: shift-click in a Finder list selected
        // only the one item instead of the range (Oct 5).
        let point = cgMouseLocation()
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        let button: CGMouseButton = right ? .right : .left
        let downType: CGEventType = right ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = right ? .rightMouseUp : .leftMouseUp
        postModifiers(source: source, flags: flags, keyDown: true)
        if !flags.isEmpty {
            waitForModifierState(flags)
            Thread.sleep(forTimeInterval: 0.03)
        }
        for index in 1...repeats {
            let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: point, mouseButton: button)
            let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: point, mouseButton: button)
            down?.flags = flags
            up?.flags = flags
            down?.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            up?.setIntegerValueField(.mouseEventClickState, value: Int64(index))
            down?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.015)
            up?.post(tap: .cghidEventTap)
            if index < repeats {
                Thread.sleep(forTimeInterval: 0.008)
            }
        }
        if !flags.isEmpty {
            Thread.sleep(forTimeInterval: 0.03)
        }
        postModifiers(source: source, flags: flags, keyDown: false)
        releaseModifiers()
        DiagnosticLog.line("Clicked \(right ? "right" : "left") flags=\(flags.rawValue) times=\(repeats) into \(frontAppName())")
    }

    public static func systemEventsKeystroke(_ key: String, command: Bool) -> Bool {
        let escaped = appleScriptEscape(key)
        let using = command ? " using command down" : ""
        let source = """
        tell application "System Events"
        keystroke "\(escaped)"\(using)
        end tell
        """
        var error: NSDictionary?
        _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            DiagnosticLog.line("System Events keystroke failed: \(error)")
            return false
        }
        return true
    }

    private static func appleScriptEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func waitForModifierState(_ flags: CGEventFlags) {
        for _ in 0..<25 {
            if CGEventSource.flagsState(.hidSystemState).contains(flags) { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
        DiagnosticLog.line("Click modifiers not visible in HID state flags=\(flags.rawValue) hid=\(CGEventSource.flagsState(.hidSystemState).rawValue)")
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
