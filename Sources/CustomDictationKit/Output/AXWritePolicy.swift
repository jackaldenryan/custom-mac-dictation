import Foundation

/// Decides whether dictation may write text through Accessibility (AX) or
/// must type with keystrokes (HID).
///
/// Why this exists: web-engine apps (Slack, Cursor, VS Code, Chrome, Safari
/// pages, OpenCode, any Electron/Chromium/WebKit view) answer AX text writes
/// with "success" but apply them late or never. Before the write is known to
/// have failed, the AX attempt has already moved the caret and selected a run
/// of the user's existing text. The HID fallback then types at that moved
/// caret, over that selection: words land in the middle of what was already
/// typed, earlier words vanish, and late-landing AX writes duplicate words.
/// (Oct 3 Slack log: every partial logged "AX write not visible in field",
/// and "hey guess what I don't know you tell me" came out as
/// "Hey, guess? I don't know you tell .me don't".)
///
/// Rule: never even attempt an AX write in a web engine, and once an app
/// shows one unconfirmed AX write, stop trying in that app for the session.
public enum AXWritePolicy {
    /// Framework bundles that mean the app renders text through a web engine.
    public static func frameworksIndicateWebEngine(_ frameworkNames: [String]) -> Bool {
        frameworkNames.contains { name in
            let n = name.lowercased()
            return n.contains("electron")
                || n.contains("chromium")
                || n.contains("chrome framework")
                || n.contains("edge framework")
                || n.contains("brave browser framework")
        }
    }

    /// Browsers and web-engine apps known by bundle ID, for ones that embed an
    /// engine without a telltale framework name.
    public static let webEngineBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.apple.Safari",
        "com.tinyspeck.slackmacgap",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
    ]

    public static func allowsAXWrite(
        bundleID: String,
        isWebEngineApp: Bool,
        focusInWebArea: Bool,
        untrustedBundleIDs: Set<String>
    ) -> Bool {
        if isWebEngineApp || focusInWebArea { return false }
        if webEngineBundleIDs.contains(bundleID) { return false }
        if untrustedBundleIDs.contains(bundleID) { return false }
        return true
    }
}

/// One phrase never switches from HID back to AX midway.
///
/// HID revisions delete backward from the caret, which is only correct if
/// every earlier piece of this phrase was typed at that caret by HID. Mixing
/// an AX attempt into an HID phrase is how the caret got moved.
public enum PhrasePathLock {
    public static func mayTryAX(phrasePath: LiveInsertPath?) -> Bool {
        phrasePath != .hid
    }
}

/// Whether dictated keystrokes may be sent to the focused element.
///
/// Why: a native (AppKit) app beeps for every keystroke that nothing takes.
/// Dictating with a Zoom meeting window in front typed each word as
/// keystrokes into the meeting view, so every phrase made a string of alert
/// "boop"s (Oct 3). The Zoom home window kept beeping (Oct 7 log: "Typed 4
/// utf16 into Zoom" outside meetings) because Zoom ships "ZoomCefHelper"
/// apps, the old web-engine test matched "cef", and web engines were exempt.
/// But an embedded web view (CEF, WKWebView) in a native app hands unhandled
/// keys back to the app, which beeps.
///
/// Rule: keystrokes go where something takes text. Only apps whose whole
/// window is a browser engine (browsers, Electron apps) are exempt: they
/// swallow unhandled keys silently, and their AX focus can lag a click into
/// a field or be missing until their accessibility tree wakes up.
public enum KeystrokePolicy {
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// Typing here starts editing (spreadsheet cells).
    static let typeToEditRoles: Set<String> = ["AXCell", "AXTable", "AXGrid"]

    /// Apps whose UI is a full browser engine. Not CEF or other embedded web
    /// views ("Chromium Embedded Framework", Zoom's "ZoomCefHelper").
    public static func swallowsUnhandledKeys(frameworkNames: [String], bundleID: String) -> Bool {
        if AXWritePolicy.webEngineBundleIDs.contains(bundleID) { return true }
        return frameworkNames.contains { name in
            let n = name.lowercased()
            return n.hasPrefix("electron framework")
                || n.hasSuffix("chrome framework.framework")
                || n.hasPrefix("chromium framework")
                || n.hasPrefix("microsoft edge framework")
                || n.hasPrefix("brave browser framework")
                || n.hasPrefix("vivaldi framework")
                || n.hasPrefix("opera framework")
        }
    }

    /// - focusedRole: nil when AX shows no focused element at all.
    /// - hasTextSelectionRange / hasInsertionPoint: a caret or text selection
    ///   (custom text views such as terminals).
    /// - isEditable: AX says the value can be set, or the element sits in
    ///   editable web content.
    public static func allowsTyping(
        swallowsUnhandledKeys: Bool,
        focusedRole: String?,
        hasTextSelectionRange: Bool,
        hasInsertionPoint: Bool,
        isEditable: Bool = false
    ) -> Bool {
        if swallowsUnhandledKeys { return true }
        // A native app with no focused element has nowhere to put text.
        guard let role = focusedRole else { return false }
        if textRoles.contains(role) || typeToEditRoles.contains(role) { return true }
        // A whole web page in a native app (Zoom home window): only if the
        // page itself is editable; a field in it is focused as its own role.
        if role == "AXWebArea" { return isEditable }
        return hasTextSelectionRange || hasInsertionPoint || isEditable
    }
}
