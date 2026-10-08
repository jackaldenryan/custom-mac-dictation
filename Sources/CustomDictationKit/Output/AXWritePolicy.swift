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

    /// Installed web apps (Chrome "Install page as app", e.g. Gmail is
    /// com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm) are their
    /// browser in a separate window: same web engine, own bundle id.
    public static func isBrowserAppShim(_ bundleID: String) -> Bool {
        webEngineBundleIDs.contains { bundleID.hasPrefix($0 + ".app.") }
    }

    public static func allowsAXWrite(
        bundleID: String,
        isWebEngineApp: Bool,
        focusInWebArea: Bool,
        untrustedBundleIDs: Set<String>
    ) -> Bool {
        if isWebEngineApp || focusInWebArea { return false }
        if webEngineBundleIDs.contains(bundleID) || isBrowserAppShim(bundleID) { return false }
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
/// Browsers and Electron apps were exempt (they never beep), so on a GitHub
/// page with no text box focused, dictated words became page shortcuts:
/// "test" typed "t", GitHub's file finder (Oct 7 log: "Typing into Google
/// Chrome (AXWebArea)", "(AXHeading)", "(AXRow)").
///
/// Rule: keystrokes go only where something takes text. In a browser that
/// means a text role or editable web content; a page, heading, row or link
/// gets nothing. Browser AX focus can lag a click into a field by a moment,
/// but that costs nothing: every new live result re-checks the focus until
/// the phrase starts typing, and each result carries the whole phrase so
/// far. A browser showing no focused element at all (accessibility tree
/// still asleep) keeps typing, since nothing can be told there.
///
/// Electron apps (Slack, Claude, Cursor) stay exempt: they send typing from
/// anywhere in the window to their message box, and the logs show dictation
/// landing there while AX reported the window ("Typing into Claude
/// (AXWebArea)", "Slack (AXGroup)").
public enum KeystrokePolicy {
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// Typing here starts editing (spreadsheet cells).
    static let typeToEditRoles: Set<String> = ["AXCell", "AXTable", "AXGrid"]

    /// Apps whose UI is a full browser engine (browsers, Electron). Not CEF
    /// or other embedded web views ("Chromium Embedded Framework", Zoom's
    /// "ZoomCefHelper"). Unhandled keys there are silent but can trigger page
    /// shortcuts.
    public static func swallowsUnhandledKeys(frameworkNames: [String], bundleID: String) -> Bool {
        if AXWritePolicy.webEngineBundleIDs.contains(bundleID) || AXWritePolicy.isBrowserAppShim(bundleID) { return true }
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

    /// Web browsers (and their installed web apps), as opposed to Electron
    /// apps: pages there have single-key shortcuts (GitHub "t", "s", ".").
    public static let browserBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "org.chromium.Chromium",
        "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
    ]

    public static func isBrowser(frameworkNames: [String], bundleID: String) -> Bool {
        if browserBundleIDs.contains(bundleID) || AXWritePolicy.isBrowserAppShim(bundleID) { return true }
        return frameworkNames.contains { name in
            let n = name.lowercased()
            return n.hasSuffix("chrome framework.framework")
                || n.hasPrefix("chromium framework")
                || n.hasPrefix("microsoft edge framework")
                || n.hasPrefix("brave browser framework")
                || n.hasPrefix("vivaldi framework")
                || n.hasPrefix("opera framework")
        }
    }

    /// - swallowsUnhandledKeys: a browser or Electron app.
    /// - isBrowser: a web browser (not Electron).
    /// - focusedRole: nil when AX shows no focused element at all.
    /// - hasTextSelectionRange / hasInsertionPoint: a caret or text selection
    ///   (custom text views such as terminals).
    /// - isEditable: AX says the value can be set, or the element sits in
    ///   editable web content.
    public static func allowsTyping(
        swallowsUnhandledKeys: Bool,
        isBrowser: Bool = false,
        focusedRole: String?,
        hasTextSelectionRange: Bool,
        hasInsertionPoint: Bool,
        isEditable: Bool = false
    ) -> Bool {
        // Electron: typing anywhere goes to the app's message box.
        if swallowsUnhandledKeys, !isBrowser { return true }
        // No focused element: a native app has nowhere to put text; a
        // browser whose accessibility tree is asleep can't be told apart.
        guard let role = focusedRole else { return swallowsUnhandledKeys || isBrowser }
        if textRoles.contains(role) { return true }
        if isBrowser {
            // Web content: only text roles or editable content (Gmail's
            // compose body, a contenteditable editor). A selection range
            // alone can be read-only page text.
            return isEditable || hasInsertionPoint
        }
        if typeToEditRoles.contains(role) { return true }
        // A whole web page in a native app (Zoom home window): only if the
        // page itself is editable; a field in it is focused as its own role.
        if role == "AXWebArea" { return isEditable }
        return hasTextSelectionRange || hasInsertionPoint || isEditable
    }
}
