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
expect(TranscriptNormalizer.isLonePunctuation("."), "lone period")
expect(TranscriptNormalizer.isLonePunctuation("?"), "lone question")
expect(!TranscriptNormalizer.isLonePunctuation(".."), "two periods not lone")
expect(!TranscriptNormalizer.isLonePunctuation("store."), "phrase with period")
expect(!TranscriptNormalizer.isLonePunctuation("hello"), "word")
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
expect(SentenceFit.midSentence("In.") == "in", "mid in")
expect(SentenceFit.midSentence("Working in development.") == "working in development", "mid strip period")
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
            isPartial: false,
            pendingLeadSpace: false,
            lastTypedAge: 5,
            lonePunctuationDelay: 1,
            isLonePunctuation: false,
            midSentence: true,
            snapshot: CaretSnapshot(before: " ", after: " ", selectedLength: 3, atStart: false)
        )
    ) == "in",
    "default mid in"
)
expect(
    DefaultPostProcess.apply(
        PostProcessInput(
            text: ".",
            isPartial: false,
            pendingLeadSpace: false,
            lastTypedAge: 0.2,
            lonePunctuationDelay: 1,
            isLonePunctuation: true,
            midSentence: false,
            snapshot: nil
        )
    ) == nil,
    "default drop leftover punct"
)
expect(
    DefaultPostProcess.apply(
        PostProcessInput(
            text: ".",
            isPartial: false,
            pendingLeadSpace: false,
            lastTypedAge: 0.2,
            lonePunctuationDelay: 0,
            isLonePunctuation: true,
            midSentence: false,
            snapshot: nil
        )
    ) == ".",
    "delay 0 keeps leftover punct"
)
if let js = try? PostProcessor.runJavaScript(
    DefaultPostProcess.javascriptSource,
    input: PostProcessInput(
        text: "In.",
        isPartial: false,
        pendingLeadSpace: false,
        lastTypedAge: 5,
        lonePunctuationDelay: 1,
        isLonePunctuation: false,
        midSentence: true,
        snapshot: CaretSnapshot(before: " ", after: " ", selectedLength: 3, atStart: false)
    )
) {
    expect(js == "in", "js default mid in")
} else {
    expect(false, "js default mid in ran")
}
expect(!AppNameResolver.discoveredApps().isEmpty, "discovers installed apps")
if let chrome = AppNameResolver.resolve("chrome") {
    expect(chrome.name.lowercased().contains("chrome"), "chrome from installed apps")
}

expect(AppSettings.default.commands.contains { $0.id == "builtin.press" }, "default includes press")
expect(Router.shouldHoldLive(transcript: "press return", state: .listening, settings: .default), "hold press")
expect(!Router.shouldHoldLive(transcript: "hello there", state: .listening, settings: .default), "live hello")
expect(!Router.shouldHoldLive(transcript: "comma", state: .listening, settings: .default), "live comma words")
expect(Router.shouldHoldLive(transcript: "press the open parentheses key", state: .listening, settings: .default), "hold press paren")
expect(
    Router.handle(
        transcript: ".",
        state: .listening,
        settings: .default,
        onStartListening: {},
        onStopListening: {}
    ) == .ignored,
    "ignore lone period"
)
expect(
    Router.handle(
        transcript: "?",
        state: .listening,
        settings: .default,
        onStartListening: {},
        onStopListening: {}
    ) == .ignored,
    "ignore lone question"
)
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
expect(liveSource.contains("Typist.typeText"), "HID types when IMK is off")
expect(liveSource.contains("setMarkedText"), "live phrase uses marked text")
expect(liveSource.contains("DictationTextInput"), "live phrase uses text input client")
expect(liveSource.contains("usesInputMethod"), "IMK is a setting")
expect(liveSource.contains("shouldFinishAXMark"), "HID commit does not AX-finish")
expect(!liveSource.contains("keepsTrailingPunctuation"), "Apple final may drop live trailing punct")
let engineSource = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Recognition/SpeechEngine.swift"), encoding: .utf8)
expect(engineSource.contains("noteFinal"), "final clears pending finalize")
expect(engineSource.contains("FinalizeGate"), "speech uses finalize gate")
expect(!AppSettings.default.useInputMethod, "IMK off by default")
 expect(!AppSettings.default.disableFinalizeDelay, "silence finalize on by default")
 expect(!AppSettings.default.postProcessOnlyOnFinal, "post-process live by default")
expect(engineSource.contains("disableForcedFinalize"), "can skip silence finalize")
expect(liveSource.contains("finishCommittedMark"), "commit always clears live mark")
expect(LiveCommitPolicy.shouldFinishAXMark(.ax), "finish live mark after AX")
expect(!LiveCommitPolicy.shouldFinishAXMark(.hid), "do not AX-finish after HID")
expect(!LiveCommitPolicy.shouldFinishAXMark(.imk), "do not AX-finish after IMK")
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
    hid.apply(shaped: "goodbye", keepSelected: false, useInputMethod: false)
    expect(hid.text == "goodbyehello world", "HID inserts into OpenCode selection")
    expect(hid.lastPath == .hid, "OpenCode uses HID")
}
do {
    let hid = SimulatedField(box: .openCode, text: "")
    hid.apply(shaped: "Testing testing?", keepSelected: true, useInputMethod: false)
    hid.apply(shaped: "Testing testing", keepSelected: false, useInputMethod: false)
    hid.apply(shaped: "?", keepSelected: false, useInputMethod: false)
    expect(hid.text == "Testing testing?", "OpenCode leftover punct must not replace the phrase")
}
do {
    let hid = SimulatedField(box: .openCode, text: "aa bb", loc: 2, len: 0)
    hid.apply(shaped: "XX", keepSelected: true, useInputMethod: false)
    expect(hid.text == "aaXX bb", "HID insert stays at clicked caret")
    expect(hid.loc == 4, "HID caret stays after mid insert")
}
do {
    let imk = SimulatedField(box: .openCode, text: "hello world", loc: 0, len: 5)
    imk.apply(shaped: "goodbye", keepSelected: false, useInputMethod: true)
    expect(imk.text == "goodbye world", "IMK replaces OpenCode selection")
    expect(imk.lastPath == .imk, "OpenCode IMK path")
}
do {
    let notes = SimulatedField(box: .notes, text: "Hi", loc: 2, len: 0)
    notes.apply(shaped: "there", keepSelected: false, useInputMethod: false)
    expect(notes.lastPath == .ax, "Notes uses AX")
    notes.finishIfNeeded()
    expect(notes.len == 0, "AX finish collapses selection")
}
do {
    let notes = SimulatedField(box: .notes, text: "")
    notes.apply(shaped: "This is a test.", keepSelected: true, useInputMethod: false)
    notes.apply(shaped: "This is a test", keepSelected: false, useInputMethod: false)
    notes.finishIfNeeded()
    expect(notes.text == "This is a test", "Apple final replaces live trailing period")
}
do {
    let notes = SimulatedField(box: .notes, text: "")
    notes.apply(shaped: "This is another test", keepSelected: true, useInputMethod: false)
    expect(notes.len == 20, "live mark selected")
    notes.apply(shaped: "This is another test", keepSelected: false, useInputMethod: false)
    notes.finishIfNeeded()
    expect(notes.len == 0, "same-text commit clears highlight")
    expect(notes.text == "This is another test", "same-text commit keeps words")
}
do {
    PlaygroundTarget.shared.isActive = true
    PlaygroundTarget.shared.deactivate()
    expect(!PlaygroundTarget.shared.isActive, "playground capture turns off")
}
do {
    let hid = SimulatedField(box: .slack, text: "ab", loc: 2, len: 0)
    hid.apply(shaped: "cd", keepSelected: false, useInputMethod: false)
    hid.finishIfNeeded()
    expect(hid.text == "abcd", "HID slack append")
}
do {
    let finderHid = SimulatedField(box: .finder, text: "")
    finderHid.apply(shaped: "hello", keepSelected: false, useInputMethod: false)
    expect(finderHid.text == "", "Finder AX/HID skips")
    expect(finderHid.lastPath == .skipped, "Finder skip path")
    let finderRelease = SimulatedField(box: .finder, text: "")
    finderRelease.apply(shaped: "hello", keepSelected: false, useInputMethod: false, forceHID: true)
    expect(finderRelease.text == "hello", "release-HID model still types in Finder")
    let finderImk = SimulatedField(box: .finder, text: "")
    finderImk.apply(shaped: "hello", keepSelected: false, useInputMethod: true)
    expect(finderImk.text == "", "Finder IMK skips")
}
do {
    let sidebar = SimulatedField(box: .notesSidebar, text: "All iCloud", loc: 0, len: 0)
    sidebar.apply(shaped: "Hello", keepSelected: true, useInputMethod: false)
    expect(sidebar.text == "All iCloud", "Notes sidebar AX/HID skips")
    expect(sidebar.lastPath == .skipped, "sidebar skip path")
}
do {
    // Suffix-diff revision: "reciept" -> "receipt" shares "rec", so 4
    // backspaces + 4 retypes instead of 7 + 7.
    let slack = SimulatedField(box: .slack, text: "")
    slack.apply(shaped: "reciept", keepSelected: true, useInputMethod: false)
    slack.apply(shaped: "receipt", keepSelected: true, useInputMethod: false)
    slack.apply(shaped: "receipt", keepSelected: false, useInputMethod: false)
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
        field.apply(shaped: p, keepSelected: true, useInputMethod: false)
    }
    field.apply(shaped: "Hey, guess what", keepSelected: false, useInputMethod: false)
    field.apply(shaped: "?", keepSelected: false, useInputMethod: false)
    for p in [" I", " I don't", " I don't know", " I don't know you", " I don't know you tell",
              " I don't know you tell me", " I don't know you tell me."] {
        field.apply(shaped: p, keepSelected: true, useInputMethod: false)
    }
    field.apply(shaped: " I don't know you tell me", keepSelected: false, useInputMethod: false)
    field.apply(shaped: ".", keepSelected: false, useInputMethod: false)
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
expect(
    InputSourceSetup.shouldPrompt(InputSourceState(installed: false, enabled: false, selected: false)),
    "missing input source prompts"
)
expect(
    !InputSourceSetup.shouldPrompt(InputSourceState(installed: true, enabled: true, selected: true)),
    "ready input source skips prompt"
)
expect(
    InputSourceSetup.shouldPrompt(InputSourceState(installed: true, enabled: true, selected: false)),
    "installed but not selected prompts"
)
expect(
    InputSourceSetup.shouldPrompt(InputSourceState(installed: true, enabled: false, selected: false)),
    "disabled input source prompts"
)
expect(LivePhrase.usesInputMethod() == false || DictationTextInput.override != nil, "default path is AX/HID")
expect(!typistSource.contains("typeViaSystemEvents"), "do not type via System Events")
let fieldSource = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Output/FieldEditor.swift"), encoding: .utf8)
expect(fieldSource.contains("caretStillInMark"), "stale live mark rejected")
expect(fieldSource.contains("restoreSelection"), "failed AX write puts the caret back")
expect(fieldSource.contains("markUntrusted"), "app with an unconfirmed AX write goes HID-only")
expect(fieldSource.contains("axWritesAllowed"), "AX writes gated by AXWritePolicy")
let infoPlist = try! String(contentsOf: repo.appendingPathComponent("Resources/Info.plist"), encoding: .utf8)
expect(infoPlist.contains("InputMethodConnectionName"), "app is an input method")
expect(infoPlist.contains("DictationInputController"), "IMK controller class")
expect(infoPlist.contains("tsVisibleInputModeOrderedArrayKey"), "input mode is listed")
expect(infoPlist.contains("TISInputSourceID"), "TIS input source id")
expect(infoPlist.contains("TISIntendedLanguage"), "TIS language")
expect(
    InputSourceSetup.inputMethodsURL(appName: "Custom Dictation Local", home: URL(fileURLWithPath: "/Users/test")).path
        == "/Users/test/Library/Input Methods/Custom Dictation Local.app",
    "input method install path"
)
let runLocal = try! String(contentsOf: repo.appendingPathComponent("scripts/run-local.sh"), encoding: .utf8)
expect(runLocal.contains("Library/Input Methods"), "local install copies into Input Methods")
let imkSource = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Output/IMKSession.swift"), encoding: .utf8)
expect(imkSource.contains("IMKInputController"), "IMK input controller")
expect(imkSource.contains("insertText"), "IMK insertText")
expect(imkSource.contains("setMarkedText"), "IMK setMarkedText")
expect(imkSource.contains("return false"), "keyboard keys pass through")

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
expect(TranscriptNormalizer.isLonePunctuation("!"), "lone bang")
expect(TranscriptNormalizer.isLonePunctuation(","), "lone comma")
expect(!TranscriptNormalizer.isLonePunctuation("..."), "ellipsis not lone")
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

LivePhrase.noteCommand()
let ageAfterCommand = Date().timeIntervalSince(LivePhrase.lastTypedAt)
expect(ageAfterCommand < 0.4, "noteCommand is recent")
expect(
    PhraseSimulation.typed(into: "Hi", transcript: ".", lastTypedAge: ageAfterCommand) == nil,
    "period after command is leftover"
)
expect(
    PhraseSimulation.typed(into: "Hi", transcript: ".", lastTypedAge: 0) == nil,
    "age zero leftover period"
)
expect(
    PhraseSimulation.typed(into: "Hi", transcript: ".", lastTypedAge: 1) == ".",
    "period after pause types"
)

expect(!Permissions.shouldShowSetup(hasCompletedOnboarding: true, accessibilityGranted: true, microphoneAuthorized: true), "setup done")
expect(Permissions.shouldShowSetup(hasCompletedOnboarding: true, accessibilityGranted: false, microphoneAuthorized: true), "ax missing shows setup")
expect(Permissions.shouldShowSetup(hasCompletedOnboarding: true, accessibilityGranted: true, microphoneAuthorized: false), "mic missing shows setup")
expect(Permissions.shouldShowSetup(hasCompletedOnboarding: false, accessibilityGranted: true, microphoneAuthorized: true), "first launch shows setup")
expect(Permissions.shouldShowSetup(hasCompletedOnboarding: false, accessibilityGranted: false, microphoneAuthorized: false), "nothing granted shows setup")

do {
    let doc = MemoryTextInput(text: "Hello world", location: 6, length: 5)
    DictationTextInput.override = doc
    defer { DictationTextInput.override = nil }
    expect(doc.isAvailable, "memory client available")
    doc.insertText("there")
    expect(doc.text == "Hello there", "insertText replaces selection")
    expect(doc.location == 11, "caret after insert")
}

do {
    let doc = MemoryTextInput(text: "", location: 0, length: 0)
    DictationTextInput.override = doc
    defer { DictationTextInput.override = nil }
    doc.setMarkedText("Hel")
    doc.setMarkedText("Hello")
    expect(doc.text == "Hello", "marked text replaces mark not append")
    doc.insertText("Hello")
    expect(doc.text == "Hello", "insert commits marked text")
}

do {
    let doc = MemoryTextInput(text: "Documents", location: 0, length: 0, isAvailable: false)
    DictationTextInput.override = doc
    defer { DictationTextInput.override = nil }
    doc.insertText("hello")
    doc.setMarkedText("hello")
    expect(doc.text == "Documents", "no client does not type")
}

do {
    let doc = MemoryTextInput(text: "hello world", location: 6, length: 5)
    DictationTextInput.override = doc
    defer { DictationTextInput.override = nil }
    expect(doc.selectedString() == "world", "selected string")
    try SelectionTransform.apply(.uppercase)
    expect(doc.text == "hello WORLD", "uppercase via text client")
}

do {
    let doc = MemoryTextInput(text: "hello", location: 5, length: 0)
    DictationTextInput.override = doc
    defer { DictationTextInput.override = nil }
    var failed = false
    do {
        try SelectionTransform.apply(.uppercase)
    } catch {
        failed = true
    }
    expect(failed, "uppercase with no selection fails")
    expect(doc.text == "hello", "no selection leaves text")
}

do {
    let doc = MemoryTextInput(text: "", location: 0, length: 0)
    DictationTextInput.override = doc
    defer { DictationTextInput.override = nil }
    expect(LivePhrase.usesInputMethod(), "override forces IMK")
    LivePhrase.displayed = ""
    LivePhrase.pendingLeadSpace = false
    LivePhrase.show("Hello")
    LivePhrase.show("Hello world")
    LivePhrase.commit("Hello world")
    expect(doc.text == "Hello world", "live phrase through text client")
}

do {
    LivePhrase.useInputMethodOverride = false
    DictationTextInput.override = nil
    defer { LivePhrase.useInputMethodOverride = nil }
    expect(!LivePhrase.usesInputMethod(), "override off is AX/HID")
}

do {
    let doc = MemoryTextInput(text: "sidebar", location: 0, length: 0, isAvailable: false)
    DictationTextInput.override = doc
    defer { DictationTextInput.override = nil }
    LivePhrase.displayed = ""
    LivePhrase.show("Hello")
    LivePhrase.commit("Hello")
    expect(doc.text == "sidebar", "live phrase skips when no client")
}

// Regression: "double punctuation and a message starting with a period".
// Oct 3 Slack log: Apple sends a sentence's closing mark as a lone final
// ("?") AND again at the start of the next segment ("? I don't know it
// seems OK"). Both got typed: "What do you think?? I don't know",
// "Let's test.. OK". Then in a new, empty field the carried-over "."
// started the message: ". OK it looks like...". Drives the real LivePhrase
// through the playground with no AX snapshot (worst case, like Slack).
do {
    let playground = PlaygroundTarget.shared
    playground.box = .slack
    playground.activate()
    defer { playground.deactivate() }
    LivePhrase.displayed = ""
    LivePhrase.noteCommand()
    LivePhrase.pendingLeadSpace = false
    func phrase(_ partials: [String], _ final: String, lone: String?) {
        for p in partials { LivePhrase.show(p) }
        LivePhrase.commit(final)
        if let lone {
            LivePhrase.lastTypedAt = .distantPast
            LivePhrase.commitLonePunctuation(lone)
        }
    }
    phrase(["What", "What do", "What do you", "What do you think", "What do you think?"], "What do you think", lone: "?")
    phrase(["I", "I don't", "I don't know", "? I don't know it", "? I don't know it seems", "? I don't know it seems.",
            "? I don't know it seems OK", "? I don't know it seems OK."], "? I don't know it seems OK", lone: ".")
    phrase(["let", "let's", "let's test", "let's test."], "let's test", lone: ".")
    phrase(["OK", "OK this", ". OK this seems", ". OK this seems de", ". OK. This seems decent", ". OK. This seems decent."],
           ". OK. This seems decent", lone: ".")
    let want = "What do you think? I don't know it seems OK. Let's test. OK. This seems decent."
    expect(playground.field.text == want, "no doubled punctuation (got \(String(reflecting: playground.field.text)))")

    // A lone mark right after one we typed is a duplicate.
    LivePhrase.lastTypedAt = .distantPast
    expect(!LivePhrase.commitLonePunctuation("."), "second period after a period is dropped")
    expect(playground.field.text == want, "field unchanged by duplicate lone period")

    // Switch to another app's empty field: the carried-over "." is dropped.
    playground.box = .notes
    phrase(["OK", ". OK it looks", ". OK it looks like that one issue is fixed"], ". OK it looks like that one issue is fixed", lone: nil)
    expect(playground.field.text == "OK it looks like that one issue is fixed",
           "new field never starts with carried-over punctuation (got \(String(reflecting: playground.field.text)))")

    // Nothing typed yet: a lone mark has nothing to close.
    playground.box = .slack
    LivePhrase.noteCommand()
    LivePhrase.lastTypedAt = .distantPast
    expect(!LivePhrase.commitLonePunctuation("."), "lone period after a command is dropped")
    expect(playground.field.text == "", "empty field stays empty")

    // Explicitly spoken punctuation inside a segment is untouched.
    LivePhrase.pendingLeadSpace = false
    phrase(["like this. And then the next sentence"], "like this. And then the next sentence", lone: ".")
    expect(playground.field.text == "Like this. And then the next sentence.", "mid-segment punctuation kept")
}
do {
    func snap(_ field: String) -> CaretSnapshot {
        InsertionContext.snapshot(in: field, utf16Location: field.utf16.count, utf16Length: 0)
    }
    expect(BoundaryPunctuation.canAttach(tail: "k", snapshot: snap("What do you think")), "mark closes our word")
    expect(BoundaryPunctuation.canAttach(tail: "k", snapshot: nil), "mark closes our word without AX")
    expect(!BoundaryPunctuation.canAttach(tail: "?", snapshot: snap("What do you think?")), "no mark after our mark")
    expect(!BoundaryPunctuation.canAttach(tail: "?", snapshot: snap("What do you think")), "our tail vetoes a stale AX caret")
    expect(!BoundaryPunctuation.canAttach(tail: nil, snapshot: snap("")), "empty field: nothing to close")
    expect(!BoundaryPunctuation.canAttach(tail: "l", snapshot: snap("")), "empty field even with a tail")
    expect(!BoundaryPunctuation.canAttach(tail: "l", snapshot: snap("Done\n")), "start of a new line")
    expect(BoundaryPunctuation.canAttach(tail: nil, snapshot: snap("working")), "user-typed word can take a spoken comma")
    expect(!BoundaryPunctuation.canAttach(tail: nil, snapshot: nil), "nothing known: drop")
    expect(BoundaryPunctuation.clean("? I don't know", canAttach: false) == "I don't know", "strip carried-over question mark")
    expect(BoundaryPunctuation.clean(". OK. This", canAttach: false) == "OK. This", "strip only the leading run")
    expect(BoundaryPunctuation.clean("?", canAttach: false) == nil, "lone mark with nothing to close")
    expect(BoundaryPunctuation.clean("? I", canAttach: true) == "? I", "attachable mark kept")
    expect(BoundaryPunctuation.clean("like this. And", canAttach: false) == "like this. And", "inner mark kept")
    expect(BoundaryPunctuation.clean("OK", canAttach: false) == "OK", "no lead, no change")
}

// Apple automatic punctuation is off by default (Oct 3): its pause guesses
// put "?" and "." mid-sentence ("or is it just? Something"). Spoken
// punctuation still works with it off: scripts/probe-punctuation.sh speaks
// "hello comma how are you question mark" and gets "Hello, how are you?".
do {
    expect(!AppSettings.default.appleAutoPunctuation, "Apple auto punctuation off by default")
    let preset = DictationTranscriber.Preset.progressiveLongDictation
    expect(!TranscriberOptions.transcription(preset: preset, autoPunctuation: false).contains(.punctuation),
           "auto punctuation off removes .punctuation")
    expect(TranscriberOptions.transcription(preset: preset, autoPunctuation: true).contains(.punctuation),
           "auto punctuation on keeps .punctuation")
    let old = #"{"hasCompletedOnboarding":true,"launchAtLogin":false}"#.data(using: .utf8)!
    let decoded = try! JSONDecoder().decode(AppSettings.self, from: old)
    expect(!decoded.appleAutoPunctuation, "settings saved before the toggle existed decode as off")
    var on = AppSettings.default
    on.appleAutoPunctuation = true
    let roundTrip = try! JSONDecoder().decode(AppSettings.self, from: try! JSONEncoder().encode(on))
    expect(roundTrip.appleAutoPunctuation, "auto punctuation setting round-trips")
    let engine = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Recognition/SpeechEngine.swift"), encoding: .utf8)
    expect(engine.contains("TranscriberOptions.transcription"), "engine builds options from the setting")
    expect(!engine.contains(".union([.punctuation])"), "engine never forces auto punctuation on")
    expect(engine.contains("lastAutoPunctuation == autoPunctuation"), "toggling rebuilds the transcriber")
}

print("CheckLogic passed")
