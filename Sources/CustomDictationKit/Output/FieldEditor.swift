import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum FieldEditor {
    private struct LiveMark {
        var element: AXUIElement
        var start: Int
    }

    nonisolated(unsafe) private static var live: LiveMark?
    /// Apps that answered an AX write with success but did not show the
    /// text. Never AX-write there again this session (see AXWritePolicy).
    nonisolated(unsafe) private static var untrustedBundleIDs: Set<String> = []
    nonisolated(unsafe) private static var webEngineCache: [String: Bool] = [:]

    public static func clearLive() {
        live = nil
    }

    public static func finishLive() {
        if let mark = live, let range = selectedRange(mark.element), range.location == mark.start {
            var caret = CFRange(location: mark.start + max(0, range.length), length: 0)
            if let value = AXValueCreate(.cfRange, &caret) {
                AXUIElementSetAttributeValue(mark.element, kAXSelectedTextRangeAttribute as CFString, value)
            }
        }
        live = nil
    }

    public static func replaceLive(with text: String, select: Bool) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        if let mark = live, isLive(mark) {
            return write(mark.element, location: mark.start, length: currentLiveLength(mark), text: text, select: select)
        }
        guard let target = usableFocusedTextElement() else { return false }
        let range = selectedRange(target) ?? CFRange(location: valueLength(target), length: 0)
        live = LiveMark(element: target, start: range.location)
        return write(target, location: range.location, length: range.length, text: text, select: select)
    }

    public static func insert(_ text: String) -> Bool {
        guard AXIsProcessTrusted(), !text.isEmpty else { return false }
        guard let target = usableFocusedTextElement() else { return false }
        let range = selectedRange(target) ?? CFRange(location: valueLength(target), length: 0)
        return write(target, location: range.location, length: range.length, text: text, select: false)
    }

    public static func selectedString() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        return firstSelectedText(from: focusedElement())
    }

    public static func replaceSelection(_ text: String) -> Bool {
        guard AXIsProcessTrusted(), let el = elementWithSelection() else { return false }
        let range = selectedRange(el) ?? CFRange(location: 0, length: 0)
        guard range.length > 0 else { return false }
        return write(el, location: range.location, length: range.length, text: text, select: false)
    }

    public static func pressAtMouse(times: Int) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let point = mouseLocation()
        var ref: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &ref) == .success,
              let start = ref,
              let target = pressable(from: start)
        else { return false }
        let repeats = min(75, max(1, times))
        for i in 0..<repeats {
            if AXUIElementPerformAction(target, kAXPressAction as CFString) != .success {
                return false
            }
            if i + 1 < repeats {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        DiagnosticLog.line("AXPress x=\(Int(point.x)) y=\(Int(point.y)) times=\(repeats)")
        return true
    }

    public static func focusedLooksLikeStub() -> Bool {
        guard let el = focusedElement() else { return false }
        return isStub(el)
    }

    /// Whether dictated keystrokes would land in something that takes text
    /// (see KeystrokePolicy), plus the focused role for the log.
    public static func focusedTakesKeystrokes() -> (allowed: Bool, role: String) {
        guard let el = focusedElement() else { return (true, "none") }
        let role = stringValue(el, kAXRoleAttribute as CFString)
        let app = owningApp(el)
        let webEngine = isWebEngineApp(app)
            || AXWritePolicy.webEngineBundleIDs.contains(app?.bundleIdentifier ?? "")
            || isInsideWebArea(el)
        var names: CFArray?
        AXUIElementCopyAttributeNames(el, &names)
        let attributes = (names as? [String]) ?? []
        let allowed = KeystrokePolicy.allowsTyping(
            isWebEngine: webEngine,
            focusedRole: role,
            hasTextSelectionRange: selectedRange(el) != nil,
            hasInsertionPoint: attributes.contains(kAXInsertionPointLineNumberAttribute as String)
        )
        return (allowed, role ?? "unknown")
    }

    private static func firstSelectedText(from start: AXUIElement?) -> String? {
        var current = start
        for _ in 0..<12 {
            guard let el = current else { return nil }
            if let selected = stringValue(el, kAXSelectedTextAttribute as CFString), !selected.isEmpty {
                return selected
            }
            current = parent(el)
        }
        return nil
    }

    private static func elementWithSelection() -> AXUIElement? {
        var current = focusedElement()
        for _ in 0..<12 {
            guard let el = current else { return nil }
            if let range = selectedRange(el), range.length > 0 { return el }
            if let selected = stringValue(el, kAXSelectedTextAttribute as CFString), !selected.isEmpty {
                return el
            }
            current = parent(el)
        }
        return nil
    }

    private static func usableFocusedTextElement() -> AXUIElement? {
        guard let el = focusedElement() else { return nil }
        if isStub(el) {
            DiagnosticLog.line("Focused AX element is a stub; skip field insert")
            return nil
        }
        guard canEditText(el) else { return nil }
        guard axWritesAllowed(el) else { return nil }
        return el
    }

    /// AX writes only where they land synchronously (native AppKit fields).
    /// Web engines must get HID only: a failed AX attempt there moves the
    /// caret before we can tell it failed.
    public static func focusedAllowsAXWrite() -> Bool {
        guard let el = focusedElement() else { return false }
        return axWritesAllowed(el)
    }

    private static func axWritesAllowed(_ el: AXUIElement) -> Bool {
        let app = owningApp(el)
        let bundleID = app?.bundleIdentifier ?? ""
        return AXWritePolicy.allowsAXWrite(
            bundleID: bundleID,
            isWebEngineApp: isWebEngineApp(app),
            focusInWebArea: isInsideWebArea(el),
            untrustedBundleIDs: untrustedBundleIDs
        )
    }

    private static func owningApp(_ el: AXUIElement) -> NSRunningApplication? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(el, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    private static func isWebEngineApp(_ app: NSRunningApplication?) -> Bool {
        guard let app, let url = app.bundleURL else { return false }
        let key = app.bundleIdentifier ?? url.path
        if let cached = webEngineCache[key] { return cached }
        let frameworks = url.appendingPathComponent("Contents/Frameworks")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        let result = AXWritePolicy.frameworksIndicateWebEngine(names)
        webEngineCache[key] = result
        return result
    }

    private static func isInsideWebArea(_ el: AXUIElement) -> Bool {
        var current: AXUIElement? = el
        for _ in 0..<40 {
            guard let node = current else { return false }
            if stringValue(node, kAXRoleAttribute as CFString) == "AXWebArea" { return true }
            current = parent(node)
        }
        return false
    }

    private static func markUntrusted(_ el: AXUIElement) {
        guard let id = owningApp(el)?.bundleIdentifier, !id.isEmpty else { return }
        if untrustedBundleIDs.insert(id).inserted {
            DiagnosticLog.line("AX writes disabled for \(id) this session; typing with keystrokes")
        }
    }

    private static func restoreSelection(_ el: AXUIElement, _ range: CFRange?) {
        guard var original = range, let value = AXValueCreate(.cfRange, &original) else { return }
        AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, value)
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused
        else { return nil }
        return (el as! AXUIElement)
    }

    private static func canEditText(_ el: AXUIElement) -> Bool {
        let role = stringValue(el, kAXRoleAttribute as CFString) ?? ""
        switch role {
        case "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField":
            break
        default:
            return false
        }
        return isSettable(el, kAXSelectedTextAttribute as CFString)
            || (isSettable(el, kAXValueAttribute as CFString) && selectedRange(el) != nil)
    }

    private static func isStub(_ el: AXUIElement) -> Bool {
        guard let frame = frame(el) else { return false }
        if frame.width < 4 || frame.height < 4 { return true }
        let role = stringValue(el, kAXRoleAttribute as CFString) ?? ""
        if frame.minX <= 2, frame.minY <= 2, frame.height <= 28, role == "AXTextField" || role == "AXTextArea" {
            return true
        }
        return false
    }

    private static func isLive(_ mark: LiveMark) -> Bool {
        guard let focused = focusedElement(), CFEqual(focused, mark.element) else { return false }
        guard let range = selectedRange(mark.element) else { return false }
        return LiveMarkLogic.caretStillInMark(caret: range.location, markStart: mark.start)
    }

    private static func currentLiveLength(_ mark: LiveMark) -> Int {
        if let range = selectedRange(mark.element), range.location == mark.start {
            return range.length
        }
        return 0
    }

    @discardableResult
    private static func write(_ el: AXUIElement, location: Int, length: Int, text: String, select: Bool) -> Bool {
        // Whatever happens, a failed write must leave the caret and selection
        // exactly where they were, so a keystroke fallback types where the
        // user expects and not over a run of their existing text.
        let original = selectedRange(el)
        var range = CFRange(location: max(0, location), length: max(0, length))
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return false }
        if AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, rangeValue) != .success {
            restoreSelection(el, original)
            return false
        }
        if AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFString) != .success {
            if !setValueBySplicing(el, location: location, length: length, text: text) {
                restoreSelection(el, original)
                return false
            }
        }
        let newLen = (text as NSString).length
        if select, !text.isEmpty {
            var selected = CFRange(location: location, length: newLen)
            if let value = AXValueCreate(.cfRange, &selected) {
                AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, value)
            }
            live = LiveMark(element: el, start: location)
        } else {
            var caret = CFRange(location: location + newLen, length: 0)
            if let value = AXValueCreate(.cfRange, &caret) {
                AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, value)
            }
            live = nil
        }
        if !confirmed(el, location: location, text: text) {
            DiagnosticLog.line("AX write not visible in field")
            live = nil
            restoreSelection(el, original)
            markUntrusted(el)
            return false
        }
        return true
    }

    private static func confirmed(_ el: AXUIElement, location: Int, text: String) -> Bool {
        if text.isEmpty { return true }
        if let selected = stringValue(el, kAXSelectedTextAttribute as CFString), selected == text {
            return true
        }
        guard let value = stringValue(el, kAXValueAttribute as CFString) else { return false }
        let ns = value as NSString
        let needle = text as NSString
        let loc = min(max(0, location), ns.length)
        if loc + needle.length <= ns.length {
            return ns.substring(with: NSRange(location: loc, length: needle.length)) == text
        }
        return value.contains(text)
    }

    private static func setValueBySplicing(_ el: AXUIElement, location: Int, length: Int, text: String) -> Bool {
        guard isSettable(el, kAXValueAttribute as CFString), let current = stringValue(el, kAXValueAttribute as CFString) else {
            return false
        }
        let ns = current as NSString
        let loc = min(max(0, location), ns.length)
        let len = min(max(0, length), ns.length - loc)
        let next = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: text)
        return AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, next as CFString) == .success
    }

    private static func pressable(from el: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = el
        for _ in 0..<10 {
            guard let node = current else { return nil }
            if actions(node).contains(kAXPressAction as String) { return node }
            current = parent(node)
        }
        return nil
    }

    private static func parent(_ el: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &ref) == .success, let ref else {
            return nil
        }
        return (ref as! AXUIElement)
    }

    private static func actions(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success, let names else { return [] }
        return (names as NSArray).compactMap { $0 as? String }
    }

    private static func selectedRange(_ el: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ax = ref
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(ax as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func valueLength(_ el: AXUIElement) -> Int {
        (stringValue(el, kAXValueAttribute as CFString) as NSString?)?.length ?? 0
    }

    private static func stringValue(_ el: AXUIElement, _ name: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func isSettable(_ el: AXUIElement, _ name: CFString) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(el, name, &settable) == .success else { return false }
        return settable.boolValue
    }

    private static func frame(_ el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    private static func mouseLocation() -> CGPoint {
        let loc = NSEvent.mouseLocation
        let maxY = NSScreen.screens.map(\.frame.maxY).max() ?? loc.y
        return CGPoint(x: loc.x, y: maxY - loc.y)
    }
}
