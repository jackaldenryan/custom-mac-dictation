import AppKit
import ApplicationServices
import Foundation

/// "command click" on a link in a browser opens it in a new background tab.
///
/// Why not just send a Command-held click: the old path asked System Events
/// to `click at {x, y}` with `key down command`. That click is an
/// Accessibility press on the element, not a real mouse event, so the held
/// Command never reaches the page and the link opens in the same tab (Oct 3
/// log: "System Events clicked left flags=1048576 ... into Google Chrome",
/// no new tab). Synthetic mouse events with Command flags and middle clicks
/// were tried before (Aug 29-30) and were unreliable too.
///
/// Instead: read the link's URL under the pointer over Accessibility
/// (AXLink -> AXURL) and ask the browser itself to open it in a new tab,
/// keeping the current tab in front, which is what Command-click does.
public enum LinkOpener {
    public enum Family: Equatable, Sendable {
        case chromium
        case safari
    }

    public static func family(bundleID: String?) -> Family? {
        guard let id = bundleID?.lowercased() else { return nil }
        if id == "com.apple.safari" || id.hasPrefix("com.apple.safaritechnologypreview") { return .safari }
        let chromium = [
            "com.google.chrome",
            "com.brave.browser",
            "com.microsoft.edgemac",
            "com.vivaldi.vivaldi",
            "org.chromium.chromium",
        ]
        return chromium.contains { id.hasPrefix($0) } ? .chromium : nil
    }

    /// AppleScript that opens `url` in a new tab of the front window and
    /// leaves the current tab active.
    public static func script(for family: Family, bundleID: String, url: String) -> String {
        let u = url.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        switch family {
        case .chromium:
            return """
            tell application id "\(bundleID)"
                set w to front window
                set i to active tab index of w
                make new tab at end of tabs of w with properties {URL:"\(u)"}
                set active tab index of w to i
            end tell
            """
        case .safari:
            return """
            tell application id "\(bundleID)"
                tell front window
                    set t to current tab
                    make new tab at end of tabs with properties {URL:"\(u)"}
                    set current tab to t
                end tell
            end tell
            """
        }
    }

    /// One step of the walk up from the element under the pointer.
    public struct Node: Equatable, Sendable {
        public var role: String?
        public var url: String?
        public init(role: String?, url: String?) {
            self.role = role
            self.url = url
        }
    }

    /// First link URL walking from the hit element up through its parents.
    /// Stops at the web area: anything above it is browser chrome.
    public static func linkURL(in path: [Node]) -> String? {
        for node in path {
            if node.role == "AXLink", let url = node.url, isOpenable(url) { return url }
            if node.role == "AXWebArea" { return nil }
        }
        return nil
    }

    /// A link found near the pointer, with its on-screen frame.
    public struct Candidate: Equatable, Sendable {
        public var url: String
        public var frame: CGRect
        public init(url: String, frame: CGRect) {
            self.url = url
            self.frame = frame
        }
    }

    /// The link whose frame contains the pointer; the smallest one wins (the
    /// most specific link, not a big card that also covers the spot).
    public static func pickLink(_ candidates: [Candidate], at point: CGPoint) -> String? {
        candidates
            .filter { isOpenable($0.url) && $0.frame.contains(point) && $0.frame.width > 0 && $0.frame.height > 0 }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?
            .url
    }

    static func isOpenable(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file://")
    }

    /// Returns true when the link under the pointer was opened in a new tab.
    public static func openLinkUnderPointerInNewTab(at point: CGPoint) -> Bool {
        guard let (element, pid) = elementAt(point) else { return false }
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier,
              let family = family(bundleID: bundleID)
        else { return false }
        var url = linkURL(in: path(from: element))
        if url == nil {
            // Chromium builds its AX tree lazily; ask for it and look again.
            AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
            if let (again, _) = elementAt(point) { url = linkURL(in: path(from: again)) }
        }
        if url == nil, let (hit, _) = elementAt(point) {
            // Button-style links: the pointer is often on a child the link
            // does not wrap (an image or label inside a card), or on an
            // overlay laid on top of the real <a>. Look inside the element
            // under the pointer and around it for a link covering the spot.
            url = pickLink(nearbyLinks(around: hit), at: point)
            if let url { DiagnosticLog.line("Command click: link found near the pointer \(url)") }
        }
        guard let url else {
            DiagnosticLog.line("Command click: no link under pointer in \(app.localizedName ?? bundleID)")
            return false
        }
        var error: NSDictionary?
        _ = NSAppleScript(source: script(for: family, bundleID: bundleID, url: url))?.executeAndReturnError(&error)
        if let error {
            DiagnosticLog.line("Command click: browser script failed (\(error[NSAppleScript.errorNumber] ?? "?")); opening \(url) in \(bundleID) directly")
            guard let link = URL(string: url), let appURL = app.bundleURL else { return false }
            NSWorkspace.shared.open([link], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            return true
        }
        DiagnosticLog.line("Command click: opened \(url) in a new tab of \(app.localizedName ?? bundleID)")
        return true
    }

    /// Links in the subtree of the element under the pointer and of its
    /// nearest ancestors (stopping at the web area). Bounded so a huge page
    /// never stalls the command.
    private static func nearbyLinks(around hit: AXUIElement, ancestors: Int = 3, maxNodes: Int = 400) -> [Candidate] {
        var roots: [AXUIElement] = [hit]
        var current = hit
        for _ in 0..<ancestors {
            guard string(current, kAXRoleAttribute) != "AXWebArea", let up = parent(current) else { break }
            if string(up, kAXRoleAttribute) == "AXWebArea" { break }
            roots.append(up)
            current = up
        }
        var found: [Candidate] = []
        var visited = 0
        // Search the widest root once: it contains the others.
        var queue: [(AXUIElement, Int)] = [(roots.last!, 0)]
        while !queue.isEmpty, visited < maxNodes {
            let (el, depth) = queue.removeFirst()
            visited += 1
            if string(el, kAXRoleAttribute) == "AXLink", let url = urlString(el), let frame = frame(el) {
                found.append(Candidate(url: url, frame: frame))
            }
            if depth < 8 {
                for child in children(el) { queue.append((child, depth + 1)) }
            }
        }
        return found
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success,
              let list = ref as? [AXUIElement]
        else { return [] }
        return list
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

    private static func elementAt(_ point: CGPoint) -> (AXUIElement, pid_t)? {
        var ref: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &ref) == .success,
              let element = ref
        else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return (element, pid)
    }

    private static func path(from start: AXUIElement) -> [Node] {
        var nodes: [Node] = []
        var current: AXUIElement? = start
        for _ in 0..<15 {
            guard let el = current else { break }
            nodes.append(Node(role: string(el, kAXRoleAttribute), url: urlString(el)))
            current = parent(el)
        }
        return nodes
    }

    private static func string(_ el: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func urlString(_ el: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXURLAttribute as CFString, &ref) == .success, let ref else { return nil }
        if let url = ref as? URL { return url.absoluteString }
        return ref as? String
    }

    private static func parent(_ el: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &ref) == .success, let ref else { return nil }
        return (ref as! AXUIElement)
    }
}
