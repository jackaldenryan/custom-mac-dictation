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
expect(TranscriptNormalizer.normalize("Stop listening, Mac.") == "stop listening mac", "normalize")
expect(AppVersion.isRemoteNewer("0.2.0", than: "0.1.0"), "newer")
expect(!AppVersion.isRemoteNewer("0.1.0", than: "0.1.0"), "same")
expect(IPAToXSampa.convert("kæt") == "k{t", "ipa")
expect(KeyPressGrammar.parse("press the open parentheses key")?.character == "(", "press open paren")
expect(KeyPressGrammar.parse("press the close parentheses key")?.character == ")", "press close paren")
expect(KeyPressGrammar.parse("press comma")?.character == ",", "press comma")
expect(KeyPressGrammar.parse("open parentheses") == nil, "open paren not a key press")
expect(!AppNameResolver.discoveredApps().isEmpty, "discovers installed apps")
if let chrome = AppNameResolver.resolve("chrome") {
    expect(chrome.name.lowercased().contains("chrome"), "chrome from installed apps")
}

expect(Router.shouldHoldLive(transcript: "press return", state: .listening, settings: .default), "hold press")
expect(!Router.shouldHoldLive(transcript: "hello there", state: .listening, settings: .default), "live hello")
expect(!Router.shouldHoldLive(transcript: "comma", state: .listening, settings: .default), "live comma words")
expect(Router.shouldHoldLive(transcript: "press the open parentheses key", state: .listening, settings: .default), "hold press paren")
expect(!Router.shouldHoldLive(transcript: "(", state: .listening, settings: .default), "live open paren char")
expect(!Router.shouldHoldLive(transcript: "{", state: .listening, settings: .default), "live open brace char")
expect(
    Router.handle(
        transcript: "(",
        state: .listening,
        settings: .default,
        onStartListening: {},
        onStopListening: {}
    ) == .typed,
    "type open paren char"
)
expect(
    Router.handle(
        transcript: "]",
        state: .listening,
        settings: .default,
        onStartListening: {},
        onStopListening: {}
    ) == .typed,
    "type close bracket char"
)

print("CheckLogic passed")
