import CoreGraphics
import CustomDictationKit
import Foundation

func expect(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

expect(KeyPressGrammar.parse("shift d") == nil, "press required")
expect(KeyPressGrammar.parse("press shift d")?.keyCode == 2, "shift d key")
expect(KeyPressGrammar.parse("press shift d")?.flags.contains(.maskShift) == true, "shift flag")
expect(KeyPressGrammar.parse("press command shift q")?.keyCode == 12, "cmd shift q")
expect(KeyPressGrammar.parse("press the one key")?.keyCode == 18, "one key")
expect(KeyPressGrammar.parse("press return")?.keyCode == 36, "return")
expect(TranscriptNormalizer.normalize("Stop listening, Mac.") == "stop listening mac", "normalize")
expect(AppVersion.isRemoteNewer("0.2.0", than: "0.1.0"), "newer")
expect(!AppVersion.isRemoteNewer("0.1.0", than: "0.1.0"), "same")
expect(IPAToXSampa.convert("kæt") == "k{t", "ipa")
expect(PunctuationPolicy.match(normalized: "comma", modes: [:]) == .typeCharacter(","), "comma")
expect(PunctuationPolicy.match(normalized: "the word comma", modes: [:]) == .typeWord("comma"), "literal comma")
print("CheckLogic passed")
