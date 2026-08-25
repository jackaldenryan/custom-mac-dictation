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
expect(!AppNameResolver.discoveredApps().isEmpty, "discovers installed apps")
if let chrome = AppNameResolver.resolve("chrome") {
    expect(chrome.name.lowercased().contains("chrome"), "chrome from installed apps")
}

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

print("CheckLogic passed")
