import CustomDictationKit
import Foundation

func focusExpect(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL focus safety: \(message)\n", stderr)
        exit(1)
    }
}

func runFocusSafetyChecks() {
    func allows(_ role: String?, range: Bool = false, editable: Bool = false,
                caret: Bool = false, browser: Bool = false, electron: Bool = false) -> Bool {
        KeystrokePolicy.allowsTyping(swallowsUnhandledKeys: browser || electron,
                                    isBrowser: browser, focusedRole: role,
                                    hasTextSelectionRange: range,
                                    hasInsertionPoint: caret, isEditable: editable)
    }
    for role in ["AXTable", "AXGrid", "AXCell", "AXOutline", "AXList",
                 "AXWindow", "AXButton", "AXCheckBox", "AXSlider", "AXStaticText"] {
        focusExpect(!allows(role), "\(role) is not a text destination")
        focusExpect(!allows(role, range: true), "a selection alone does not make \(role) editable")
    }
    focusExpect(!allows(nil, browser: true), "missing browser focus must not send page shortcuts")
    focusExpect(!allows("AXGroup", electron: true), "Electron framework is not proof of a text destination")
    for role in ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"] {
        focusExpect(allows(role, editable: true), "editable \(role) still accepts dictation")
        focusExpect(allows(role, caret: true), "custom \(role) with a caret still accepts dictation")
        focusExpect(!allows(role, range: true), "read-only \(role) selection does not permit typing")
    }
    focusExpect(allows("AXGroup", editable: true, browser: true), "editable browser content still types")
    focusExpect(allows("AXTextArea", editable: true, electron: true), "Electron composer still types")
    focusExpect(!KeystrokePolicy.allowsTyping(swallowsUnhandledKeys: false,
        focusedRole: "AXTextField", hasTextSelectionRange: true,
        hasInsertionPoint: true, isEditable: true, isEnabled: false), "disabled text input stays silent")
    for role in ["AXSlider", "AXCheckBox", "AXButton", "AXOutline", "AXRow"] {
        focusExpect(!allows(role, editable: true, caret: true), "non-text \(role) cannot be overridden by misleading signals")
    }
    print("Focus policy checks passed")
}

private final class RecordingDictationOutput: DictationOutput {
    enum Edit: Equatable {
        case ax(String)
        case key(DictationKeyEvent, Int32)
        case finish
    }
    var focus: DictationTarget?
    var edits: [Edit] = []
    var axWorks = false
    var axAttempts = 0
    var duringAX: (() -> Void)?
    var afterKey: (() -> Void)?
    var frontAppID: String { "app-\(focus?.processID ?? -1)" }
    func target() -> DictationTarget? { focus }
    func snapshot() -> CaretSnapshot? { nil }
    func replaceLive(_ text: String, select: Bool, target: DictationTarget) -> Bool {
        axAttempts += 1
        duringAX?()
        guard focus == target, axWorks else { return false }
        edits.append(.ax(text))
        return true
    }
    private var keys: DictationKeyWriter {
        DictationKeyWriter(currentTarget: { self.focus }, post: { event, pid in
            self.edits.append(.key(event, pid))
            self.afterKey?()
        })
    }
    func typeText(_ text: String, target: DictationTarget) -> Bool { keys.write(text, target: target) }
    func deleteBackward(_ count: Int, target: DictationTarget) -> Bool { keys.deleteBackward(count, target: target) }
    func finishLive(target: DictationTarget) {
        if focus == target { edits.append(.finish) }
    }
    func clearLive() {}
}

func runLiveFocusChecks() {
    // No simulatedField shortcut: these drive the production applyAXHid
    // state machine and the same guarded key emitter used by Typist.
    let previousOutput = LivePhrase.output
    let previousSimulation = LivePhrase.simulatedField
    let recording = RecordingDictationOutput()
    LivePhrase.simulatedField = nil
    LivePhrase.output = recording
    DiagnosticLog.isEnabled = false
    defer {
        recording.focus = nil
        LivePhrase.keepAndUnhighlight()
        LivePhrase.output = previousOutput
        LivePhrase.simulatedField = previousSimulation
    }
    let chat = DictationTarget(processID: 100, elementID: "chat")
    let otherApp = DictationTarget(processID: 200, elementID: "chat")
    let otherField = DictationTarget(processID: 100, elementID: "search")
    func reset(ax: Bool = false) {
        recording.focus = nil
        LivePhrase.keepAndUnhighlight()
        LivePhrase.noteCommand()
        LivePhrase.pendingLeadSpace = false
        recording.edits = []
        recording.axWorks = ax
        recording.axAttempts = 0
        recording.duringAX = nil
        recording.afterKey = nil
        recording.focus = chat
    }
    var cases = 0
    // Both HID and AX phrases must stop on a non-text view, app switch,
    // or another field in the SAME app. Cover append, correction, and final.
    for ax in [false, true] {
        for destination in [nil, otherApp, otherField] as [DictationTarget?] {
            for revised in ["hello world", "help", "hello"] {
                reset(ax: ax)
                LivePhrase.show("hello")
                focusExpect(!recording.edits.isEmpty, "initial phrase really emitted input")
                let before = recording.edits
                recording.focus = destination
                LivePhrase.show(revised)
                focusExpect(recording.edits == before, "focus switch emits no append, correction, or selection change")
                // Even returning to the original text field must not replay
                // the accumulated transcript after a focus loss.
                recording.focus = chat
                LivePhrase.show("hello world again")
                LivePhrase.commit("hello world again")
                focusExpect(recording.edits == before, "remainder and final stay suppressed after focus returns")
                LivePhrase.show("new sentence")
                focusExpect(recording.edits.count > before.count, "next phrase recovers")
                cases += 1
            }
        }
    }
    for ax in [false, true] {
        reset(ax: ax)
        LivePhrase.show("hello")
        let before = recording.edits
        recording.focus = otherField
        LivePhrase.discard()
        focusExpect(recording.edits == before, "discard never deletes from a new field")
        cases += 1
        reset(ax: ax)
        LivePhrase.show("hello")
        let kept = recording.edits
        recording.focus = nil
        LivePhrase.keepAndUnhighlight()
        focusExpect(recording.edits == kept, "stop listening never edits the departed field")
        recording.focus = chat
        LivePhrase.show("next")
        focusExpect(recording.edits.count > kept.count, "stop resets cancelled phrase state")
        cases += 1
    }
    reset()
    recording.focus = nil
    LivePhrase.show("hello")
    focusExpect(recording.edits.isEmpty && recording.axAttempts == 0, "no focus blocks both AX and HID")
    recording.focus = chat
    LivePhrase.commit("hello")
    focusExpect(!recording.edits.isEmpty, "initial AX focus lag can recover before any text was inserted")
    cases += 1

    reset(ax: true)
    LivePhrase.show("hello")
    let beforeFallback = recording.edits
    recording.duringAX = { recording.focus = otherField }
    LivePhrase.show("hello world")
    focusExpect(recording.edits == beforeFallback, "focus loss during AX never enters HID fallback")
    cases += 1

    reset(ax: true)
    LivePhrase.show("hello")
    recording.axWorks = false
    LivePhrase.show("hello world")
    focusExpect(recording.edits.last == .key(.text(Array("Hello world".utf16)), chat.processID),
                "AX failure in same field still falls back to HID")
    let attempts = recording.axAttempts
    LivePhrase.commit("hello world again")
    focusExpect(recording.axAttempts == attempts, "phrase stays HID after fallback")
    cases += 1

    reset()
    LivePhrase.show("hello")
    recording.afterKey = { recording.focus = otherField }
    let beforeDelete = recording.edits.count
    LivePhrase.show("hi")
    focusExpect(recording.edits.count == beforeDelete + 1, "focus loss during correction stops remaining backspaces AND replacement")
    focusExpect(recording.edits.last == .key(.backspace, chat.processID), "first correction key addressed original process")
    cases += 1

    reset()
    recording.afterKey = { recording.focus = nil }
    LivePhrase.show(String(repeating: "word ", count: 20))
    focusExpect(recording.edits.count == 1, "long text stops after focus changes during first chunk")
    recording.afterKey = nil
    recording.focus = chat
    LivePhrase.commit("word")
    focusExpect(recording.edits.count == 1, "partial emission failure suppresses remaining phrase")
    cases += 1

    reset()
    LivePhrase.show("hello")
    LivePhrase.show("help")
    LivePhrase.commit("help")
    let typed = recording.edits.compactMap { edit -> String? in
        if case .key(.text(let units), _) = edit { return String(decoding: units, as: UTF16.self) }
        return nil
    }
    focusExpect(typed == ["Hello", "p"], "same-field suffix correction preserved")
    focusExpect(recording.edits.filter { $0 == .key(.backspace, chat.processID) }.count == 2,
                "same-field correction deletes only differing suffix")
    cases += 1

    // Shared emission boundary: a stale target cannot type or delete even
    // if a higher-level caller forgets its own guard.
    reset()
    recording.focus = otherField
    focusExpect(!recording.typeText("oops", target: chat), "stale target rejects literal text")
    focusExpect(!recording.deleteBackward(4, target: chat), "stale target rejects deletion")
    focusExpect(recording.edits.isEmpty, "stale target emitted zero keys")
    cases += 1
    reset()
    let unicode = String(repeating: "x", count: 19) + "👨‍👩‍👧‍👦" + "é"
    focusExpect(recording.typeText(unicode, target: chat), "Unicode text succeeds")
    let chunks = recording.edits.compactMap { edit -> [UInt16]? in
        if case .key(.text(let units), _) = edit { return units }; return nil
    }
    focusExpect(chunks.flatMap { $0 } == Array(unicode.utf16), "chunking preserves every Unicode unit")
    focusExpect(chunks.allSatisfy { !String(decoding: $0, as: UTF16.self).contains("�") }, "chunks never split surrogate pairs")
    cases += 1
    print("Live focus safety: \(cases) scenarios passed (real phrase state machine + guarded key emitter)")
}
