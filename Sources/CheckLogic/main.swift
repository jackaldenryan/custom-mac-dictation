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
DictationSpacing.reset()

expect(KeyPressGrammar.parse("shift d") == nil, "press required")
expect(KeyPressGrammar.parse("press shift d")?.keyCode == 2, "shift d key")
expect(KeyPressGrammar.parse("press shift d")?.flags.contains(.maskShift) == true, "shift flag")
expect(KeyPressGrammar.parse("press the shift c key")?.keyCode == 8, "shift c key")
expect(KeyPressGrammar.parse("press the shift c key")?.flags.contains(.maskShift) == true, "shift c flag")
expect(KeyPressGrammar.parse("press the shift c key")?.character == nil, "shift c no unicode override")
expect(KeyPressGrammar.parse("press command shift q")?.keyCode == 12, "cmd shift q")
expect(KeyPressGrammar.parse("press the one key")?.keyCode == 18, "one key")
expect(KeyPressGrammar.parse("press return")?.keyCode == 36, "return")
expect(TranscriptNormalizer.normalize("Stop listening, Mac.") == "stop listening mac", "normalize")
expect(AppVersion.isRemoteNewer("0.2.0", than: "0.1.0"), "newer")
expect(!AppVersion.isRemoteNewer("0.1.0", than: "0.1.0"), "same")
expect(IPAToXSampa.convert("kæt") == "k{t", "ipa")
expect(PunctuationPolicy.match(normalized: "comma", modes: [:]) == .typeCharacter(","), "comma")
expect(PunctuationPolicy.match(normalized: "the word comma", modes: [:]) == .typeWord("comma"), "literal comma")
expect(PunctuationPolicy.match(normalized: "open parentheses", modes: [:]) == .typeCharacter("("), "open parentheses")
expect(PunctuationPolicy.match(normalized: "close parentheses", modes: [:]) == .typeCharacter(")"), "close parentheses")
expect(PunctuationPolicy.match(normalized: "open parenthesis", modes: [:]) == .typeCharacter("("), "open parenthesis")
expect(PunctuationPolicy.match(normalized: "question mark", modes: [:]) == .typeCharacter("?"), "question mark")
expect(PunctuationPolicy.match(normalized: "asterisk", modes: [:]) == .typeCharacter("*"), "asterisk")
expect(!AppNameResolver.discoveredApps().isEmpty, "discovers installed apps")
if let chrome = AppNameResolver.resolve("chrome") {
    expect(chrome.name.lowercased().contains("chrome"), "chrome from installed apps")
}

expect(Router.shouldHoldLive(transcript: "press return", state: .listening, settings: .default), "hold press")
expect(!Router.shouldHoldLive(transcript: "hello there", state: .listening, settings: .default), "live hello")
expect(Router.shouldHoldLive(transcript: "open parentheses", state: .listening, settings: .default), "hold punctuation")

DictationSpacing.reset()
expect(DictationSpacing.preview("a") == "a", "preview first")
_ = DictationSpacing.textToType("a")
expect(DictationSpacing.preview("b") == " b", "preview lead space")
DictationSpacing.reset()
expect(DictationSpacing.textToType("a") == "a", "first phrase no lead space")
expect(DictationSpacing.textToType("b") == " b", "second phrase lead space")
expect(DictationSpacing.punctuationToType(",") == ",", "comma no lead space")
expect(DictationSpacing.textToType("c") == " c", "word after comma")
DictationSpacing.reset()
_ = DictationSpacing.textToType("hello")
expect(DictationSpacing.punctuationToType("(") == " (", "open paren lead space")
expect(DictationSpacing.textToType("world") == "world", "no space after open paren")

print("CheckLogic passed")
