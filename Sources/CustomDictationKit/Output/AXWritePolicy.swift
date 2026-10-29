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

/// Dictation requires a text destination in every app. Framework names,
/// selectable text, and generic table/cell roles are not editing permission.
/// Earlier browser/Electron exemptions let speech trigger page shortcuts;
/// native table exemptions also let typing reach Finder and Zoom controls.
public enum KeystrokePolicy {
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// These controls must not become text inputs merely because AX exposes
    /// a numeric/bool value, selection, or a spurious insertion point.
    static let nonTextControls: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXSlider", "AXStepper",
        "AXMenu", "AXMenuItem", "AXMenuBar", "AXToolbar", "AXTabGroup",
        "AXWindow", "AXApplication", "AXImage", "AXLink",
        "AXOutline", "AXList", "AXBrowser", "AXRow", "AXScrollArea",
    ]

    /// A settable AXValue is not, by itself, proof of editable text: macOS
    /// also exposes it for controls such as scrollers and Finder's Desktop.
    /// Only known text roles may use that signal. Custom editors must expose
    /// a settable selected-text attribute or an editable ancestor instead.
    public static func hasEditableTextEvidence(
        focusedRole: String,
        valueSettable: Bool,
        selectedTextSettable: Bool,
        hasEditableAncestor: Bool
    ) -> Bool {
        selectedTextSettable
            || hasEditableAncestor
            || (textRoles.contains(focusedRole) && valueSettable)
    }

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

    /// Whether an AXInsertionPointLineNumber value means a real text caret.
    /// Chrome answers NSNotFound (Int.max) for elements with no caret: a
    /// GitHub file row in the log read "caret=9223372036854775807" and was
    /// taken as a caret, so typing went to the page (Oct 7).
    public static func isCaret(lineNumber: Int?) -> Bool {
        guard let line = lineNumber else { return false }
        return line >= 0 && line != NSNotFound
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
    /// - bundleID: owning app; Finder is fail-closed outside real text roles
    ///   because its Desktop and file views handle typing as file actions.
    /// - hasTextSelectionRange / hasInsertionPoint: a caret or text selection
    ///   (custom text views such as terminals).
    /// - isEditable: AX says the value can be set, or the element sits in
    ///   editable web content.
    public static func allowsTyping(
        swallowsUnhandledKeys: Bool,
        isBrowser: Bool = false,
        bundleID: String = "",
        focusedRole: String?,
        hasTextSelectionRange: Bool,
        hasInsertionPoint: Bool,
        isEditable: Bool = false,
        isEnabled: Bool = true
    ) -> Bool {
        // Fail closed when AX cannot identify a destination. A later live
        // result can retry before any text is inserted.
        guard isEnabled, let role = focusedRole else { return false }
        if bundleID == "com.apple.finder", !textRoles.contains(role) { return false }
        if nonTextControls.contains(role) { return false }
        if textRoles.contains(role) { return isEditable || hasInsertionPoint }
        // A table or a selected cell may be a file browser, not a sheet.
        // Require actual editing evidence instead of assuming type-to-edit.
        if ["AXCell", "AXTable", "AXGrid", "AXWebArea"].contains(role) {
            return isEditable
        }
        // Text selections can be read-only. The AX layer validates writable
        // text rather than treating every settable value as editable text.
        return isEditable || hasInsertionPoint
    }
}
