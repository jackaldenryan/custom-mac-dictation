import CoreGraphics
import CustomDictationKit
import Foundation

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

SoundFeedback.isEnabled = false

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
expect(!liveSource.contains("hidReplace"), "live phrase does not HID")
expect(!liveSource.contains("Typist.typeText"), "live phrase does not fake a keyboard")
expect(liveSource.contains("setMarkedText"), "live phrase uses marked text")
expect(liveSource.contains("DictationTextInput"), "live phrase uses text input client")
expect(!typistSource.contains("typeViaSystemEvents"), "do not type via System Events")
let fieldSource = try! String(contentsOf: repo.appendingPathComponent("Sources/CustomDictationKit/Output/FieldEditor.swift"), encoding: .utf8)
expect(fieldSource.contains("caretStillInMark"), "stale live mark rejected")
let infoPlist = try! String(contentsOf: repo.appendingPathComponent("Resources/Info.plist"), encoding: .utf8)
expect(infoPlist.contains("InputMethodConnectionName"), "app is an input method")
expect(infoPlist.contains("DictationInputController"), "IMK controller class")
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
    LivePhrase.displayed = ""
    LivePhrase.pendingLeadSpace = false
    LivePhrase.show("Hello")
    LivePhrase.show("Hello world")
    LivePhrase.commit("Hello world")
    expect(doc.text == "Hello world", "live phrase through text client")
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

print("CheckLogic passed")
