import CustomDictationKit
import Foundation

enum Checks {
    nonisolated(unsafe) static var failures = 0

    static func check(_ name: String, _ got: String?, _ want: String?) {
        if got == want { return }
        failures += 1
        fputs("FAIL: \(name)\n  got: \(got.map { String(reflecting: $0) } ?? "nil")\n  want: \(want.map { String(reflecting: $0) } ?? "nil")\n", stderr)
    }
}

func check(_ name: String, _ got: String?, _ want: String?) {
    Checks.check(name, got, want)
}

func typed(
    _ field: String,
    _ transcript: String,
    age: Double = 5,
    pending: Bool = false
) -> String? {
    PhraseSimulation.typed(into: field, transcript: transcript, lastTypedAge: age, pendingLeadSpace: pending)
}

check("empty field keeps capital, no space", typed("", "Hello"), "Hello")
check("newline after period is sentence start", typed("Done.\n", "Hello"), "Hello")
check("newline after word is sentence start", typed("Done\n", "Hello"), "Hello")
check("bullet is sentence start", typed("• ", "Hello"), "Hello")
check("dash bullet is sentence start", typed("- ", "Hello"), "Hello")
check("asterisk bullet is sentence start", typed("* ", "Hello"), "Hello")

check("after period plus space, capitalize, no extra space", typed("Done. ", "Hello"), "Hello")
check("after question plus space, capitalize, no extra space", typed("Done? ", "Hello"), "Hello")
check("after bang plus space, capitalize, no extra space", typed("Done! ", "Hello"), "Hello")
check("after period with no space, prefix one space and capitalize", typed("Done.", "Hello"), " Hello")
check("after question with no space, prefix one space and capitalize", typed("Done?", "Hello"), " Hello")
check("comma is mid-sentence, not sentence start", typed("Done, ", "Hello"), "hello")

check("mid-sentence lowercase, prefix space", typed("working", "In the lab"), " in the lab")
check("mid-sentence existing space, no extra space", typed("working ", "In the lab"), "in the lab")
check("mid-sentence keep I pronoun", typed("working ", "I think"), "I think")

check("drop leftover period within 0.4s", typed("Hi", ".", age: 0.2), nil)
check("drop leftover question within 0.4s", typed("Hi", "?", age: 0.2), nil)
check("allow lone period after delay", typed("Hi", ".", age: 1), ".")
check("allow word after 0.4s", typed("Hi", "a", age: 1), " a")

check("do not add a period", typed("", "Hello"), "Hello")
check("keep a period at sentence start", typed("", "Hello."), "Hello.")
check("keep question mark at sentence start", typed("", "Hello?"), "Hello?")
check("strip leftover period mid-sentence", typed("working ", "Hello."), "hello")
check("strip leftover question mid-sentence", typed("working ", "Hello?"), "hello")

check("no space before comma mid-sentence", typed("working", ", and"), ", and")
check("no space before semicolon mid-sentence", typed("working", "; and"), "; and")
check("no space before slash mid-sentence", typed("working", "/path"), "/path")

check("keep acronym ROFL mid-sentence", typed("say ", "ROFL"), "ROFL")
check("keep acronym ASAP mid-sentence", typed("say ", "ASAP"), "ASAP")
check("keep acronym OK mid-sentence", typed("say ", "OK"), "OK")

do {
    let js = try PhraseSimulation.typedJavaScript(into: "working ", transcript: "In")
    check("js matches swift mid-sentence", js, PhraseSimulation.typed(into: "working ", transcript: "In"))
} catch {
    check("js mid-sentence", error.localizedDescription, nil)
}

if Checks.failures > 0 {
    fputs("CheckPhraseRules: \(Checks.failures) failed\n", stderr)
    exit(1)
}

print("CheckPhraseRules passed")
