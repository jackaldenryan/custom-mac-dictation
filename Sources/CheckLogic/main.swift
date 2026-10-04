import CoreGraphics
import CustomDictationKit
import Foundation
import Speech

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

SoundFeedback.isEnabled = false
DiagnosticLog.isEnabled = false

expect(KeyPressGrammar.parse("shift d") == nil, "press required")
expect(KeyPressGrammar.parse("command click") == nil, "click is not key grammar")
expect(!CommandSpec.builtIns.isEmpty, "shipped command JSON loaded")
expect(CommandSpec.builtIns.contains { $0.action == .click && $0.phrases.contains("command click") }, "default command click")
expect(CommandSpec.builtIns.contains { $0.action == .click && $0.phrases.contains("right click") }, "default right click")
expect(CommandSpec.builtIns.contains { $0.id == "builtin.double-click" && $0.clickTimes == 2 }, "default double click")
expect(CommandSpec.builtIns.contains { $0.id == "builtin.triple-click" && $0.clickTimes == 3 }, "default triple click")
expect(ClickGrammar.parse("option click")?.flags.contains(.maskAlternate) == true, "option click")
expect(ClickGrammar.parse("command option click")?.flags.contains(.maskCommand) == true, "command option click")
expect(ClickGrammar.parse("command shift click")?.flags.contains(.maskShift) == true, "command shift click")
expect(ClickGrammar.parse("control click")?.flags.contains(.maskControl) == true, "control click")
expect(ClickGrammar.parse("click") == nil, "plain click not grammar")
expect(Router.shouldHoldLive(transcript: "option click", state: .listening, settings: .default), "hold option click")
expect(CommandSpec.builtIns.contains { $0.match == .appSlot && $0.phrases.contains("open {app}") }, "open app slot")
expect(CommandSpec.builtIns.contains { $0.match == .appSlot && $0.phrases.contains("quit {app}") }, "quit app slot")
expect(Router.shouldHoldLive(transcript: "command click", state: .listening, settings: .default), "hold command click")
expect(!Router.shouldHoldLive(transcript: "comma", state: .listening, settings: .default), "comma not command click")
expect(KeyPressGrammar.parse("press shift d")?.keyCode == 2, "shift d key")
expect(KeyPressGrammar.parse("press shift d")?.flags.contains(.maskShift) == true, "shift flag")
expect(KeyPressGrammar.parse("press the shift c key")?.keyCode == 8, "shift c key")
expect(KeyPressGrammar.parse("press the shift c key")?.flags.contains(.maskShift) == true, "shift c flag")
expect(KeyPressGrammar.parse("press the shift c key")?.character == nil, "shift c no unicode override")
expect(KeyPressGrammar.parse("press command shift q")?.keyCode == 12, "cmd shift q")
expect(KeyPressGrammar.parse("press the one key")?.keyCode == 18, "one key")
expect(KeyPressGrammar.parse("press return")?.keyCode == 36, "return")
expect(TranscriptNormalizer.normalize("Stop listening, dictation.") == "stop listening dictation", "normalize")
expect(AppVersion.isRemoteNewer("0.2.0", than: "0.1.0"), "newer")
expect(!AppVersion.isRemoteNewer("0.1.0", than: "0.1.0"), "same")
expect(IPAToXSampa.convert("kæt") == "k{t", "ipa")
expect(KeyPressGrammar.parse("press the open parentheses key")?.keyCode == 25, "press open paren")
expect(KeyPressGrammar.parse("press the open parentheses key")?.flags.contains(.maskShift) == true, "open paren shift")
expect(KeyPressGrammar.parse("press the close parentheses key")?.keyCode == 29, "press close paren")
expect(KeyPressGrammar.parse("press comma")?.keyCode == 43, "press comma")
expect(KeyPressGrammar.parse("open parentheses") == nil, "open paren not a key press")
expect(KeyPressGrammar.parse("press the open square bracket key")?.keyCode == 33, "open square")
expect(KeyPressGrammar.parse("press the close square bracket key")?.keyCode == 30, "close square")
expect(KeyPressGrammar.parse("press the [ key")?.keyCode == 33, "symbol open square")
expect(KeyPressGrammar.parse("press the question mark key")?.keyCode == 44, "question mark")
expect(KeyPressGrammar.parse("press the question mark key")?.flags.contains(.maskShift) == true, "question mark shift")
expect(KeyPressGrammar.parse("press the ? key")?.keyCode == 44, "symbol question")
expect(KeyPressGrammar.parse("press the tilde key")?.keyCode == 50, "tilde")
expect(KeyPressGrammar.parse("press the tilde key")?.flags.contains(.maskShift) == true, "tilde shift")
expect(KeyPressGrammar.parse("press the open angle bracket key")?.keyCode == 43, "open angle")
expect(KeyPressGrammar.parse("press the open angle bracket key")?.flags.contains(.maskShift) == true, "open angle shift")
expect(KeyPressGrammar.parse("press the close angle bracket key")?.keyCode == 47, "close angle")
expect(KeyPressGrammar.parse("press shift period")?.keyCode == 47, "shift period")
expect(KeyPressGrammar.parse("press shift period")?.flags.contains(.maskShift) == true, "shift period flag")
expect(KeyPressGrammar.parse("press command shift left bracket")?.keyCode == 33, "cmd shift bracket")
expect(KeyPressGrammar.parse("press command shift left bracket")?.flags.contains(.maskCommand) == true, "cmd on bracket")
expect(KeyPressGrammar.parse("press command shift left bracket")?.flags.contains(.maskShift) == true, "shift on bracket")
expect(KeyPressGrammar.parse("press the page down key")?.keyCode == 121, "page down")
expect(KeyPressGrammar.parse("press the page up key")?.keyCode == 116, "page up")
expect(KeyPressGrammar.parse("press the page down key five times")?.keyCode == 121, "page down five")
expect(KeyPressGrammar.parse("press the page down key five times")?.times == 5, "page down five count")
expect(KeyPressGrammar.parse("press return 3 times")?.times == 3, "return three")
expect(KeyPressGrammar.parse("press tab twice")?.times == 2, "tab twice")
expect(KeyPressGrammar.parse("press delete seventy five times")?.times == 75, "seventy five")
expect(KeyPressGrammar.parse("press delete 100 times")?.times == 75, "clamp 75")
expect(KeyPressGrammar.parse("press the tilde key")?.keyCode == 50, "tilde")
expect(KeyPressGrammar.parse("press tilda")?.keyCode == 50, "tilda")
expect(KeyPressGrammar.parse("press the backtick key")?.keyCode == 50, "backtick")
expect(KeyPressGrammar.parse("press the back tick key")?.flags.isEmpty == true, "backtick unshifted")
expect(KeyPressGrammar.parse("press the vertical bar key")?.keyCode == 42, "vertical bar")
expect(KeyPressGrammar.parse("press the caret key")?.keyCode == 22, "caret")
expect(KeyPressGrammar.parse("press the number one key")?.keyCode == 18, "number one")
expect(KeyPressGrammar.parse("Press, the one key.")?.keyCode == 18, "press one with comma")
expect(KeyPressGrammar.parse("press, the one key")?.keyCode == 18, "press one comma")
expect(KeyPressGrammar.parse("press ~")?.keyCode == 50, "tilde symbol")
expect(KeyPressGrammar.parse("press `")?.keyCode == 50, "backtick symbol")
expect(KeyPressGrammar.parse("press ^")?.keyCode == 22, "caret symbol")
expect(KeyPressGrammar.parse("press |")?.keyCode == 42, "pipe symbol")
expect(Router.shouldHoldLive(transcript: "open", state: .listening, settings: .default), "hold open")
expect(Router.shouldHoldLive(transcript: "open safari", state: .listening, settings: .default), "hold open safari")
expect(Router.shouldHoldLive(transcript: "upper case that", state: .listening, settings: .default), "hold upper case")
expect(Router.shouldHoldLive(transcript: "upper", state: .listening, settings: .default), "hold upper")
expect(SentenceFit.midSentence("In.") == "in.", "mid lowers capital, keeps spoken period")
expect(SentenceFit.midSentence("Working in development.") == "working in development.", "mid keeps spoken period")
expect(SentenceFit.midSentence("Really?") == "really?", "mid keeps spoken question mark")
expect(SentenceFit.midSentence("I think") == "I think", "keep pronoun I")
expect(InsertionContext.leadingCharacterImpliesSentenceStart("Hello. ", utf16Location: 7), "after period")
expect(!InsertionContext.leadingCharacterImpliesSentenceStart("working ", utf16Location: 8), "mid word")
expect(
    !FieldFit.needsLeadSpace(
        "in",
        snapshot: CaretSnapshot(before: " ", after: " ", selectedLength: 3, atStart: false),
        pendingLeadSpace: true
    ),
    "no space when replacing selection"
)
expect(
    !FieldFit.needsLeadSpace(
        ",",
        snapshot: CaretSnapshot(before: "t", after: " ", selectedLength: 0, atStart: false),
        pendingLeadSpace: true
    ),
    "no space before comma"
)
expect(
    FieldFit.needsLeadSpace(
        "in",
        snapshot: CaretSnapshot(before: "g", after: nil, selectedLength: 0, atStart: false),
        pendingLeadSpace: false
    ),
    "space after a letter"
)
expect(
    !FieldFit.needsLeadSpace(
        "in",
        snapshot: CaretSnapshot(before: " ", after: "t", selectedLength: 0, atStart: false),
        pendingLeadSpace: true
    ),
    "no space after existing space"
)
expect(
    DefaultPostProcess.apply(
        PostProcessInput(
            text: "In.",
            pendingLeadSpace: false,
            midSentence: true,
            snapshot: CaretSnapshot(before: " ", after: " ", selectedLength: 3, atStart: false)
        )
    ) == "in.",
    "default mid-sentence keeps the spoken period, lowers Apple's capital"
)
expect(
    DefaultPostProcess.apply(
        PostProcessInput(
            text: ".",
            pendingLeadSpace: true,
            midSentence: false,
            snapshot: nil
        )
    ) == ".",
    "spoken lone period types, no lead space"
)
expect(!AppNameResolver.discoveredApps().isEmpty, "discovers installed apps")
if let chrome = AppNameResolver.resolve("chrome") {
    expect(chrome.name.lowercased().contains("chrome"), "chrome from installed apps")
}

expect(AppSettings.default.commands.contains { $0.id == "builtin.press" }, "default includes press")
expect(Router.shouldHoldLive(transcript: "press return", state: .listening, settings: .default), "hold press")
expect(!Router.shouldHoldLive(transcript: "hello there", state: .listening, settings: .default), "live hello")
expect(!Router.shouldHoldLive(transcript: "comma", state: .listening, settings: .default), "live comma words")
expect(Router.shouldHoldLive(transcript: "press the open parentheses key", state: .listening, settings: .default), "hold press paren")
do {
    // A lone mark is spoken punctuation now (Apple auto punctuation off), so
    // the router types it. The simulated field keeps it from typing for real.
    LivePhrase.simulatedField = SimulatedField(box: .notes)
    defer { LivePhrase.simulatedField = nil; LivePhrase.displayed = "" }
    expect(
        Router.handle(
            transcript: ".",
            state: .listening,
            settings: .default,
            onStartListening: {},
            onStopListening: {}
        ) == .typed,
        "lone spoken period is typed"
    )
    expect(
        Router.handle(
            transcript: "?",
            state: .listening,
            settings: .default,
            onStartListening: {},
            onStopListening: {}
        ) == .typed,
        "lone spoken question mark is typed"
    )
    expect(
        Router.handle(
            transcript: "?",
            state: .suspended,
            settings: .default,
            onStartListening: {},
            onStopListening: {}
        ) == .ignored,
        "suspended still ignores a lone mark"
    )
}
expect(
    Router.handle(
        transcript: "hello there",
        state: .suspended,
        settings: .default,
        onStartListening: {},
        onStopListening: {}
    ) == .ignored,
    "suspended ignores dictation"
)
var started = false
expect(
    Router.handle(
        transcript: "start listening dictation",
        state: .suspended,
        settings: .default,
        onStartListening: { started = true },
        onStopListening: {}
    ) == .handled && started,
    "start listening while suspended"
)
var stopped = false
expect(
    Router.handle(
        transcript: "stop listening dictation",
        state: .listening,
        settings: .default,
        onStartListening: {},
        onStopListening: { stopped = true }
    ) == .handled && stopped,
    "stop listening while listening"
)

expect(LiveMarkLogic.caretStillInMark(caret: 4, markStart: 4), "live mark only at start")
expect(!LiveMarkLogic.caretStillInMark(caret: 12, markStart: 4), "click away from live mark")

let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let typistSource = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Output/Typist.swift"), encoding: .utf8)
let liveSource = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Output/LivePhrase.swift"), encoding: .utf8)
expect(!typistSource.contains("selectBackward"), "never shift-select live phrase")
expect(typistSource.contains("releaseModifiers"), "release stuck modifiers")
expect(!liveSource.contains("selectBackward"), "live phrase does not shift-select")
expect(liveSource.contains("hidReplace"), "AX/HID path kept")
expect(liveSource.contains("hidFallbackAllowed"), "Finder/sidebar never dictated")
expect(liveSource.contains("commonPrefixKeepCount"), "HID suffix-diff revision")
expect(liveSource.contains("Typist.typeText"), "HID typing path")
expect(liveSource.contains("shouldFinishAXMark"), "HID commit does not AX-finish")
expect(!liveSource.contains("keepsTrailingPunctuation"), "Apple final may drop live trailing punct")
let engineSource = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Recognition/SpeechEngine.swift"), encoding: .utf8)
expect(engineSource.contains("noteFinal"), "final clears pending finalize")
expect(engineSource.contains("FinalizeGate"), "speech uses finalize gate")
 expect(!AppSettings.default.disableFinalizeDelay, "silence finalize on by default")
expect(engineSource.contains("disableForcedFinalize"), "can skip silence finalize")
expect(liveSource.contains("finishCommittedMark"), "commit always clears live mark")
expect(LiveCommitPolicy.shouldFinishAXMark(.ax), "finish live mark after AX")
expect(!LiveCommitPolicy.shouldFinishAXMark(.hid), "do not AX-finish after HID")
expect(!LiveCommitPolicy.shouldFinishAXMark(.skipped), "do not AX-finish when skipped")
do {
    var gate = FinalizeGate()
    let t0 = Date()
    gate.notePartial(at: t0)
    expect(gate.shouldForceFinalize(delay: 0.7, now: t0.addingTimeInterval(0.7)), "force finalize after silence")
    gate.noteFinal()
    expect(!gate.shouldForceFinalize(delay: 0.7, now: t0.addingTimeInterval(2)), "final clears pending finalize")
    gate.notePartial(at: t0.addingTimeInterval(2.1))
    expect(!gate.shouldForceFinalize(delay: 0.7, now: t0.addingTimeInterval(2.2)), "new phrase not finalized instantly")
}
do {
    let hid = SimulatedField(box: .openCode, text: "hello world", loc: 0, len: 5)
    hid.apply(shaped: "goodbye", keepSelected: false)
    expect(hid.text == "goodbyehello world", "HID inserts into OpenCode selection")
    expect(hid.lastPath == .hid, "OpenCode uses HID")
}
do {
    let hid = SimulatedField(box: .openCode, text: "")
    hid.apply(shaped: "Testing testing?", keepSelected: true)
    hid.apply(shaped: "Testing testing", keepSelected: false)
    hid.apply(shaped: "?", keepSelected: false)
    expect(hid.text == "Testing testing?", "OpenCode leftover punct must not replace the phrase")
}
do {
    let hid = SimulatedField(box: .openCode, text: "aa bb", loc: 2, len: 0)
    hid.apply(shaped: "XX", keepSelected: true)
    expect(hid.text == "aaXX bb", "HID insert stays at clicked caret")
    expect(hid.loc == 4, "HID caret stays after mid insert")
}
do {
    let notes = SimulatedField(box: .notes, text: "Hi", loc: 2, len: 0)
    notes.apply(shaped: "there", keepSelected: false)
    expect(notes.lastPath == .ax, "Notes uses AX")
    notes.finishIfNeeded()
    expect(notes.len == 0, "AX finish collapses selection")
}
do {
    let notes = SimulatedField(box: .notes, text: "")
    notes.apply(shaped: "This is a test.", keepSelected: true)
    notes.apply(shaped: "This is a test", keepSelected: false)
    notes.finishIfNeeded()
    expect(notes.text == "This is a test", "Apple final replaces live trailing period")
}
do {
    let notes = SimulatedField(box: .notes, text: "")
    notes.apply(shaped: "This is another test", keepSelected: true)
    expect(notes.len == 20, "live mark selected")
    notes.apply(shaped: "This is another test", keepSelected: false)
    notes.finishIfNeeded()
    expect(notes.len == 0, "same-text commit clears highlight")
    expect(notes.text == "This is another test", "same-text commit keeps words")
}
do {
    let hid = SimulatedField(box: .slack, text: "ab", loc: 2, len: 0)
    hid.apply(shaped: "cd", keepSelected: false)
    hid.finishIfNeeded()
    expect(hid.text == "abcd", "HID slack append")
}
do {
    let finderHid = SimulatedField(box: .finder, text: "")
    finderHid.apply(shaped: "hello", keepSelected: false)
    expect(finderHid.text == "", "Finder AX/HID skips")
    expect(finderHid.lastPath == .skipped, "Finder skip path")
    let finderRelease = SimulatedField(box: .finder, text: "")
    finderRelease.apply(shaped: "hello", keepSelected: false, forceHID: true)
    expect(finderRelease.text == "hello", "release-HID model still types in Finder")
}
do {
    let sidebar = SimulatedField(box: .notesSidebar, text: "All iCloud", loc: 0, len: 0)
    sidebar.apply(shaped: "Hello", keepSelected: true)
    expect(sidebar.text == "All iCloud", "Notes sidebar AX/HID skips")
    expect(sidebar.lastPath == .skipped, "sidebar skip path")
}
do {
    // Suffix-diff revision: "reciept" -> "receipt" shares "rec", so 4
    // backspaces + 4 retypes instead of 7 + 7.
    let slack = SimulatedField(box: .slack, text: "")
    slack.apply(shaped: "reciept", keepSelected: true)
    slack.apply(shaped: "receipt", keepSelected: true)
    slack.apply(shaped: "receipt", keepSelected: false)
    expect(slack.text == "receipt", "HID suffix-diff keeps the words")
    expect(slack.deletedUnits == 4, "HID suffix-diff deletes only the tail")
    expect(slack.insertedUnits == 7 + 4, "HID suffix-diff retypes only the tail")
}
do {
    expect(LivePhrase.commonPrefixKeepCount("reciept", "receipt") == 3, "common prefix of correction")
    expect(LivePhrase.commonPrefixKeepCount("Hello", "Hello world") == 5, "common prefix of growth")
    expect(LivePhrase.commonPrefixKeepCount("abc", "xyz") == 0, "no common prefix")
}
// Regression: "Slack cursor jumps back and types inside earlier words".
// Oct 3 log, saying "hey guess what I don't know you tell me" in Slack:
// every partial tried an AX write ("AX write not visible in field"), which
// moved Slack's caret to a stale spot before HID typed there. Result was
// "Hey, guess? I don't know you tell .me don't". Phrases must only append.
func slackLogReplay(_ field: SimulatedField) {
    for p in ["Hey, guess", "Hey, guess what", "Hey, guess what?"] {
        field.apply(shaped: p, keepSelected: true)
    }
    field.apply(shaped: "Hey, guess what", keepSelected: false)
    field.apply(shaped: "?", keepSelected: false)
    for p in [" I", " I don't", " I don't know", " I don't know you", " I don't know you tell",
              " I don't know you tell me", " I don't know you tell me."] {
        field.apply(shaped: p, keepSelected: true)
    }
    field.apply(shaped: " I don't know you tell me", keepSelected: false)
    field.apply(shaped: ".", keepSelected: false)
}
do {
    let want = "Hey, guess what? I don't know you tell me."
    for box in [FieldBox.slack, .cursorEditor, .openCode, .googleSearch, .chromeURL] {
        let fixed = SimulatedField(box: box, text: "")
        slackLogReplay(fixed)
        expect(fixed.text == want, "\(box.title): dictation only appends (got \(String(reflecting: fixed.text)))")
        expect(fixed.loc == (want as NSString).length, "\(box.title): caret ends after the dictation")
    }
    let preFix = SimulatedField(box: .slack, text: "")
    preFix.probeAXInWebEngines = true
    slackLogReplay(preFix)
    expect(preFix.text != want, "pre-fix replay still reproduces the cursor-jump bug (keeps the model honest)")
    let withPrior = SimulatedField(box: .slack, text: "Earlier message. ")
    slackLogReplay(withPrior)
    expect(withPrior.text == "Earlier message. " + want, "Slack: earlier text untouched, dictation appended")
}
do {
    // AXWritePolicy: web engines never get AX writes.
    expect(AXWritePolicy.frameworksIndicateWebEngine(["Electron Framework.framework", "Squirrel.framework"]), "Electron app detected")
    expect(AXWritePolicy.frameworksIndicateWebEngine(["Google Chrome Framework.framework"]), "Chrome detected")
    expect(AXWritePolicy.frameworksIndicateWebEngine(["Chromium Embedded Framework.framework"]), "CEF detected")
    expect(!AXWritePolicy.frameworksIndicateWebEngine(["Sparkle.framework", "ServiceFramework.framework"]), "native frameworks not web")
    expect(!AXWritePolicy.allowsAXWrite(bundleID: "com.tinyspeck.slackmacgap", isWebEngineApp: false, focusInWebArea: false, untrustedBundleIDs: []), "Slack never AX-writes")
    expect(!AXWritePolicy.allowsAXWrite(bundleID: "x.electron.app", isWebEngineApp: true, focusInWebArea: false, untrustedBundleIDs: []), "Electron never AX-writes")
    expect(!AXWritePolicy.allowsAXWrite(bundleID: "dev.tauri.app", isWebEngineApp: false, focusInWebArea: true, untrustedBundleIDs: []), "web area never AX-writes")
    expect(!AXWritePolicy.allowsAXWrite(bundleID: "com.example.flaky", isWebEngineApp: false, focusInWebArea: false, untrustedBundleIDs: ["com.example.flaky"]), "app with a failed AX write stays HID")
    expect(AXWritePolicy.allowsAXWrite(bundleID: "com.apple.Notes", isWebEngineApp: false, focusInWebArea: false, untrustedBundleIDs: []), "Notes keeps AX live mark")
    expect(PhrasePathLock.mayTryAX(phrasePath: nil), "new phrase may try AX")
    expect(PhrasePathLock.mayTryAX(phrasePath: .ax), "AX phrase keeps AX")
    expect(!PhrasePathLock.mayTryAX(phrasePath: .hid), "HID phrase never switches to AX")
    expect(liveSource.contains("PhrasePathLock"), "live phrase uses the path lock")
    expect(!liveSource.contains("FieldEditor.hasSelection()"), "no AX-guessed backspace before HID typing")
}
expect(FieldBox.allCases.contains(.openCode), "opencode box exists")
expect(!typistSource.contains("typeViaSystemEvents"), "do not type via System Events")
let fieldSource = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Output/FieldEditor.swift"), encoding: .utf8)
expect(fieldSource.contains("caretStillInMark"), "stale live mark rejected")
expect(fieldSource.contains("restoreSelection"), "failed AX write puts the caret back")
expect(fieldSource.contains("markUntrusted"), "app with an unconfirmed AX write goes HID-only")
expect(fieldSource.contains("axWritesAllowed"), "AX writes gated by AXWritePolicy")
let infoPlist = try! String(contentsOf: repo.appendingPathComponent("Resources/Info.plist"), encoding: .utf8)
expect(!infoPlist.contains("InputMethodConnectionName"), "not an input method (IMK removed in 0.1.40)")
let runLocal = try! String(contentsOf: repo.appendingPathComponent("scripts/run-local.sh"), encoding: .utf8)
expect(!runLocal.contains("Input Methods"), "local install no longer copies into Input Methods")

expect(ClickGrammar.parse("double click")?.times == 2, "double click")
expect(ClickGrammar.parse("triple click")?.times == 3, "triple click")
expect(ClickGrammar.parse("right click")?.right == true, "right click")
expect(ClickGrammar.parse("command double click")?.times == 2, "command double click")
expect(ClickGrammar.parse("command double click")?.flags.contains(.maskCommand) == true, "command on double click")
expect(ClickGrammar.parse("shift right click")?.right == true, "shift right click")
expect(ClickGrammar.parse("press command click")?.flags.contains(.maskCommand) == true, "press command click")
expect(ClickGrammar.parse("hello click") == nil, "hello click not grammar")
expect(ClickGrammar.shouldHold("command"), "hold command toward click")
expect(ClickGrammar.shouldHold("double"), "hold double toward click")
expect(!ClickGrammar.shouldHold("hello"), "hello not click hold")
expect(Router.shouldHoldLive(transcript: "triple click", state: .listening, settings: .default), "hold triple click")
expect(Router.shouldHoldLive(transcript: "right click", state: .listening, settings: .default), "hold right click")
expect(Router.shouldHoldLive(transcript: "capitalize that", state: .listening, settings: .default), "hold capitalize that")
expect(Router.shouldHoldLive(transcript: "lowercase that", state: .listening, settings: .default), "hold lowercase that")
expect(KeyPressGrammar.parse("press the c key")?.keyCode == 8, "press c")
expect(KeyPressGrammar.parse("press the p key")?.keyCode == 35, "press p")
expect(KeyPressGrammar.parse("press space")?.keyCode == 49, "press space")
expect(KeyPressGrammar.parse("press escape")?.keyCode == 53, "press escape")
expect(KeyPressGrammar.parse("press the delete key")?.keyCode == 51, "press delete")
expect(KeyPressGrammar.parse("press down")?.keyCode == 125, "press down")
expect(KeyPressGrammar.parse("press up")?.keyCode == 126, "press up")
expect(KeyPressGrammar.parse("press left")?.keyCode == 123, "press left")
expect(KeyPressGrammar.parse("press right")?.keyCode == 124, "press right")
expect(TranscriptNormalizer.normalize("Uppercase that.") == "uppercase that", "normalize uppercase that")
expect(TranscriptNormalizer.normalize("  Hello,  World!  ") == "hello world", "normalize extra space")
expect(LiveMarkLogic.caretStillInMark(caret: 0, markStart: 0), "mark at zero")
expect(!LiveMarkLogic.caretStillInMark(caret: 1, markStart: 0), "caret moved one")
expect(!LiveMarkLogic.caretStillInMark(caret: 0, markStart: 8), "caret before mark")
expect(CommandSpec.builtIns.contains { $0.action == .uppercase }, "builtin uppercase")
expect(CommandSpec.builtIns.contains { $0.action == .lowercase }, "builtin lowercase")
expect(CommandSpec.builtIns.contains { $0.action == .capitalize }, "builtin capitalize")
expect(CommandSpec.builtIns.contains { $0.phrases.contains("uppercase that") }, "uppercase that phrase")
expect(
    Router.handle(
        transcript: "",
        state: .listening,
        settings: .default,
        onStartListening: {},
        onStopListening: {}
    ) == .ignored,
    "empty transcript ignored"
)
expect(Router.shouldHoldLive(transcript: "hello", state: .suspended, settings: .default), "suspended holds live")

expect(PhraseSimulation.typed(into: "Hi", transcript: ".") == ".", "spoken period after a word types")

expect(!Permissions.shouldShowSetup(hasCompletedOnboarding: true, accessibilityGranted: true, microphoneAuthorized: true), "setup done")
expect(Permissions.shouldShowSetup(hasCompletedOnboarding: true, accessibilityGranted: false, microphoneAuthorized: true), "ax missing shows setup")
expect(Permissions.shouldShowSetup(hasCompletedOnboarding: true, accessibilityGranted: true, microphoneAuthorized: false), "mic missing shows setup")
expect(Permissions.shouldShowSetup(hasCompletedOnboarding: false, accessibilityGranted: true, microphoneAuthorized: true), "first launch shows setup")
expect(Permissions.shouldShowSetup(hasCompletedOnboarding: false, accessibilityGranted: false, microphoneAuthorized: false), "nothing granted shows setup")

// Spoken punctuation is always typed (Apple automatic punctuation off).
// Regression for "saying question mark after an existing ? does nothing":
// the old boundary-punctuation filter dropped any mark that followed a mark
// we typed (it existed only for Apple's repeated auto-punctuation guesses).
// Drives the real LivePhrase and Router into a simulated field with no AX
// snapshot (worst case, like Slack). Finals arrive as Apple sends them with
// auto punctuation off (scripts/probe-punctuation.sh): "Guess what?" then a
// lone "?" for a second spoken "question mark".
do {
    var field = SimulatedField(box: .slack)
    LivePhrase.simulatedField = field
    defer { LivePhrase.simulatedField = nil }
    LivePhrase.displayed = ""
    LivePhrase.noteCommand()
    LivePhrase.pendingLeadSpace = false
    func say(_ partials: [String], _ final: String) {
        for p in partials { LivePhrase.show(p) }
        let route = Router.handle(transcript: final, state: .listening, settings: .default, onStartListening: {}, onStopListening: {})
        expect(route == .typed, "\(String(reflecting: final)) is typed, not ignored")
    }
    say(["Guess", "Guess what", "Guess what?"], "Guess what?")
    say(["?"], "?")
    expect(field.text == "Guess what??", "second spoken ? after an existing ? (got \(String(reflecting: field.text)))")
    say([], "!")
    expect(field.text == "Guess what??!", "spoken ! after ?")
    say(["I", "I don't know"], "I don't know.")
    expect(field.text == "Guess what??! I don't know.", "sentence after our ? starts capitalized with one space")
    say([], ",")
    say(["and more"], ", and more")
    expect(field.text == "Guess what??! I don't know.,, and more",
           "every spoken mark types, even right after another (got \(String(reflecting: field.text)))")

    // A spoken mark in a new, empty field is still typed: the user said it.
    field = SimulatedField(box: .notes)
    LivePhrase.simulatedField = field
    say([], ".")
    expect(field.text == ".", "spoken period into an empty field")

    // Mid-sentence insert keeps a spoken period but lowers Apple's capital.
    field = SimulatedField(box: .slack)
    LivePhrase.simulatedField = field
    LivePhrase.noteCommand()
    LivePhrase.pendingLeadSpace = false
    say([], "Working")
    say([], "Now.")
    expect(field.text == "Working now.", "mid-sentence keeps spoken period (got \(String(reflecting: field.text)))")
}

// Apple automatic punctuation is always off (0.1.40): its pause guesses put
// "?" and "." mid-sentence ("or is it just? Something"), and the typing
// logic assumes every mark was spoken. scripts/probe-punctuation.sh checks
// that spoken punctuation still converts ("hello comma how are you question
// mark" -> "Hello, how are you?").
do {
    let preset = DictationTranscriber.Preset.progressiveLongDictation
    expect(!TranscriberOptions.transcription(preset: preset, autoPunctuation: false).contains(.punctuation),
           "auto punctuation off removes .punctuation")
    expect(TranscriberOptions.transcription(preset: preset, autoPunctuation: true).contains(.punctuation),
           "probe can still turn it on")
    let engine = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Recognition/SpeechEngine.swift"), encoding: .utf8)
    expect(engine.contains("TranscriberOptions.transcription(preset: preset, autoPunctuation: false)"), "app always runs with auto punctuation off")
    let window = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/App/MainWindowController.swift"), encoding: .utf8)
    expect(!window.contains("automatic punctuation"), "no auto punctuation toggle (it would bring back doubled marks)")
    expect(!window.contains("Input Method"), "no IMK toggle")
    expect(!window.contains("Playground"), "no Playground tab in the app")
    let live = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Output/LivePhrase.swift"), encoding: .utf8)
    expect(live.contains("simulatedField"), "tests drive LivePhrase through a simulated field")
}


do {
    // Settings saved by older versions (post-process configs, pause delay)
    // still load; the removed keys are ignored.
    let old = #"{"hasCompletedOnboarding":true,"postProcessOnlyOnFinal":true,"activePostProcessID":"x","postProcessConfigs":[],"lonePunctuationDelaySeconds":2,"punctuationModes":{},"useInputMethod":true,"appleAutoPunctuation":true}"#.data(using: .utf8)!
    let decoded = try? JSONDecoder().decode(AppSettings.self, from: old)
    expect(decoded?.hasCompletedOnboarding == true, "old settings with removed keys still decode")
    let window = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/App/MainWindowController.swift"), encoding: .utf8)
    expect(!window.contains("Post-process"), "no Post-process tab")
    let folder = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Support/ConfigFolder.swift"), encoding: .utf8)
    expect(folder.contains("removeItem(at: legacyPostProcessURL)"), "stale post-process.json is cleaned up")
}

// "command click" on a link opens it in a new tab (Oct 3: it didn't in
// Chrome). The System Events click it used is an Accessibility press, so the
// held Command never reached the page. Now: link URL from AX, opened by the
// browser in a new background tab.
do {
    typealias N = LinkOpener.Node
    expect(LinkOpener.linkURL(in: [N(role: "AXStaticText", url: nil), N(role: "AXLink", url: "https://example.com/a"), N(role: "AXWebArea", url: "https://example.com")])
           == "https://example.com/a", "link found by walking up from the text under the pointer")
    expect(LinkOpener.linkURL(in: [N(role: "AXButton", url: nil), N(role: "AXWebArea", url: "https://example.com"), N(role: "AXLink", url: "https://x.com")]) == nil,
           "nothing above the web area counts (browser chrome)")
    expect(LinkOpener.linkURL(in: [N(role: "AXLink", url: "javascript:void(0)")]) == nil, "script links fall back to a real click")
    expect(LinkOpener.family(bundleID: "com.google.Chrome") == .chromium, "Chrome uses the Chromium script")
    expect(LinkOpener.family(bundleID: "com.apple.Safari") == .safari, "Safari script")
    expect(LinkOpener.family(bundleID: "com.apple.finder") == nil, "Finder command click stays a click")
    let chrome = LinkOpener.script(for: .chromium, bundleID: "com.google.Chrome", url: "https://example.com/?q=\"x\"")
    expect(chrome.contains("make new tab at end of tabs of w"), "Chrome opens a new tab")
    expect(chrome.contains("set active tab index of w to i"), "Chrome keeps the current tab in front, like Command-click")
    expect(chrome.contains(#"q=\"x\""#), "URL quotes escaped for AppleScript")
    let typist = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Output/Typist.swift"), encoding: .utf8)
    expect(typist.contains("LinkOpener.openLinkUnderPointerInNewTab"), "command click tries the link path first")
    expect(ClickGrammar.parse("command click mouse")?.flags == .maskCommand, "command click mouse")
    expect(ClickGrammar.parse("right click mouse")?.right == true, "right click mouse")
    expect(ClickGrammar.parse("click mouse") == nil, "plain click mouse is the exact command, not grammar")
    expect(CommandSpec.builtIns.contains { $0.action == .click && $0.phrases.contains("click mouse") && ($0.clickTimes ?? 1) == 1 },
           "\"click mouse\" clicks")
}

// Commands run from live text once it is a whole command and has been
// stable for EarlyCommand.settleSeconds, instead of waiting 1-2 s for
// Apple's final (Oct 3: "open slack", "capitalize that" felt slow). The
// final that follows must not run or type the command a second time.
do {
    let s = AppSettings.default
    expect(Router.isEarlyCommand(transcript: "capitalize that", state: .listening, settings: s), "capitalize that runs early")
    expect(Router.isEarlyCommand(transcript: "press the down key", state: .listening, settings: s), "key press runs early")
    expect(Router.isEarlyCommand(transcript: "command click", state: .listening, settings: s), "click grammar runs early")
    expect(!Router.isEarlyCommand(transcript: "capitalize that", state: .suspended, settings: s), "nothing early while paused")
    expect(!Router.isEarlyCommand(transcript: "hello there", state: .listening, settings: s), "dictation never runs early")
    expect(!Router.isEarlyCommand(transcript: "open zzqqxx", state: .listening, settings: s), "open with no matching app waits for the final")
    if AppNameResolver.resolve("finder") != nil {
        expect(Router.isEarlyCommand(transcript: "open finder", state: .listening, settings: s), "open an installed app runs early")
    }
    expect(AppSettings.default.commandSettleSeconds == 0.2, "commands run 0.2 s after the words settle by default")
    expect(AppSettings.clampedCommandSettle(9) == 3 && AppSettings.clampedCommandSettle(-1) == 0, "command pause clamped to 0-3 s")
    expect(DelaySettings(AppSettings.default).commandSettleSeconds == 0.2, "command pause saved in delays.json")
    let oldDelays = #"{"finalizeDelaySeconds":0.4,"keyRepeatDelaySeconds":0.08}"#.data(using: .utf8)!
    expect((try? JSONDecoder().decode(DelaySettings.self, from: oldDelays))?.commandSettleSeconds == 0.2, "older delays.json gets the 0.2 s default")
    let sessionSource = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Recognition/ListeningSession.swift"), encoding: .utf8)
    expect(sessionSource.contains("store.settings.commandSettleSeconds"), "session uses the command pause setting")
    let now = Date()
    let ran = EarlyCommand.Ran(normalized: "open slack", at: now)
    expect(EarlyCommand.resolveFinal("open Slack", ran: ran, now: now) == .skip, "final of an early command is skipped")
    expect(EarlyCommand.resolveFinal("Open slack.", ran: ran, now: now) == .skip, "case and punctuation ignored")
    expect(EarlyCommand.resolveFinal("open snack", ran: ran, now: now) == .skip, "reworded same-length final is not typed")
    expect(EarlyCommand.resolveFinal("open Slack and then type hello", ran: ran, now: now) == .route("and then type hello"), "words after the command still route")
    expect(EarlyCommand.resolveFinal("open Slack", ran: nil, now: now) == .route("open Slack"), "no early command: normal route")
    expect(EarlyCommand.resolveFinal("open Slack", ran: ran, now: now.addingTimeInterval(30)) == .route("open Slack"), "stale early command does not swallow a later one")
    let session = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Recognition/ListeningSession.swift"), encoding: .utf8)
    expect(session.contains("Router.isEarlyCommand") && session.contains("EarlyCommand.resolveFinal"), "session runs commands early and skips their final")
}

print("CheckLogic passed")
