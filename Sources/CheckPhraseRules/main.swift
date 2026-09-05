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
    pending: Bool = false,
    partial: Bool = false
) -> String? {
    PhraseSimulation.typed(
        into: field,
        transcript: transcript,
        lastTypedAge: age,
        pendingLeadSpace: pending,
        isPartial: partial
    )
}

check("empty field keeps capital, no space", typed("", "Hello"), "Hello")
check("newline after period is sentence start", typed("Done.\n", "Hello"), "Hello")
check("newline after word is sentence start", typed("Done\n", "Hello"), "Hello")
check("bullet is sentence start", typed("• ", "Hello"), "Hello")
check("dash bullet is sentence start", typed("- ", "Hello"), "Hello")
check("asterisk bullet is sentence start", typed("* ", "Hello"), "Hello")

check("after period plus space, capitalize, no extra space", typed("Done. ", "Hello"), "Hello")
check("after question, capitalize lowercase yes", typed("Guess what?", "yes"), " Yes")
check("after question plus space, capitalize lowercase yes", typed("Guess what? ", "yes"), "Yes")
check("empty field capitalizes lowercase", typed("", "yes"), "Yes")
check("after question plus space, capitalize, no extra space", typed("Done? ", "Hello"), "Hello")
check("after bang plus space, capitalize, no extra space", typed("Done! ", "Hello"), "Hello")
check("after period with no space, prefix one space and capitalize", typed("Done.", "Hello"), " Hello")
check("after question with no space, prefix one space and capitalize", typed("Done?", "Hello"), " Hello")
check("comma is mid-sentence, not sentence start", typed("Done, ", "Hello"), "hello")
check("after comma with no space, prefix space", typed("Let’s see about this,", "testing"), " testing")
check("after closing paren, prefix space", typed("hello)", "there"), " there")
check("after closing paren, no space before period", typed("hello)", "."), ".")
check("after closing paren, no space before comma", typed("hello)", ","), ",")
check("after closing bracket, no space before period", typed("hello]", "."), ".")
check("after closing quote, prefix space", typed("hello\"", "there"), " there")
check("after slash, no space", typed("foo/", "bar"), "bar")
check("after hyphen, no space", typed("well-", "known"), "known")

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
check("keep acronym NASA mid-sentence", typed("see ", "NASA"), "NASA")
check("keep iPhone capital mid-sentence", typed("buy ", "iPhone"), "iPhone")
check("keep I'm mid-sentence", typed("because ", "I'm here"), "I'm here")
check("mid-sentence I'll stays", typed("because ", "I'll go"), "I'll go")
check("number at sentence start", typed("", "42"), "42")
check("number mid-sentence no extra rules", typed("got ", "42"), "42")
check("after colon capitalize", typed("Note: ", "hello"), "hello")
check("after semicolon mid", typed("wait; ", "Hello"), "hello")
check("ellipsis is sentence start", typed("Wait… ", "Hello"), "Hello")
check("after newline indent still sentence start", typed("Done.\n\n", "hello"), "Hello")
check("drop leftover bang within 0.4s", typed("Hi", "!", age: 0.2), nil)
check("drop leftover comma within 0.4s", typed("Hi", ",", age: 0.2), nil)
check("allow lone bang after delay", typed("Hi", "!", age: 1), "!")
check("no space before colon mid-sentence", typed("working", ": yes"), ": yes")
check("opening paren no extra space after existing space", typed("see ", "(hello"), "(hello")
check("opening paren after letter gets space", typed("see", "(hello"), " (hello")
check("closing-style quote attaches", typed("said", "\"hi"), "\"hi")
check("don't double space", typed("working  ", "Hello"), "hello")
check("tab after word is mid-sentence", typed("Done\t", "Hello"), "hello")
check("keep ellipsis at start", typed("", "Hello..."), "Hello...")
check("strip leftover ellipsis mid-sentence", typed("working ", "Hello..."), "hello")
check("question after letter no space", typed("right", "?"), "?")
check("bang after letter no space", typed("wow", "!"), "!")
check("space already before question", typed("right ", "?"), "?")
check("first word of empty is capital", typed("", "the"), "The")
check("mid keep all-caps two letters", typed("code ", "ID"), "ID")
check("after closing brace space", typed("hello}", "there"), " there")
check("after em dash space", typed("wait—", "hello"), " hello")
do {
    let js = try PhraseSimulation.typedJavaScript(into: "Hi", transcript: ".", lastTypedAge: 0.2)
    check("js matches swift leftover period drop", js, typed("Hi", ".", age: 0.2))
} catch {
    check("js leftover period drop", error.localizedDescription, nil)
}

do {
    let js = try PhraseSimulation.typedJavaScript(into: "working ", transcript: "In")
    check("js matches swift mid-sentence", js, PhraseSimulation.typed(into: "working ", transcript: "In"))
} catch {
    check("js mid-sentence", error.localizedDescription, nil)
}

check("partial matches final empty hello", typed("", "hello", partial: true), typed("", "hello"))
check("partial matches final mid-sentence", typed("working ", "In the lab", partial: true), typed("working ", "In the lab"))
check("partial leftover period still dropped", typed("Hi", ".", age: 0.2, partial: true), nil)
check("partial leftover question still dropped", typed("Hi", "?", age: 0.2, partial: true), nil)
check("partial keeps capital at start", typed("", "Hello", partial: true), "Hello")
check("partial strips leftover period mid-sentence", typed("working ", "Hello.", partial: true), "hello")
do {
    let js = try PhraseSimulation.typedJavaScript(into: "working ", transcript: "In the lab", isPartial: true)
    check("js partial matches swift", js, typed("working ", "In the lab", partial: true))
} catch {
     check("js partial", error.localizedDescription, nil)
 }

 do {
     var settings = AppSettings.default
     settings.postProcessOnlyOnFinal = true
     let live = PhraseSimulation.input(into: "working", transcript: "In the lab", isPartial: true)
     check("live skip post-process when only-on-final", PostProcessor.process(live, settings: settings), "In the lab")
     let fin = PhraseSimulation.input(into: "working", transcript: "In the lab", isPartial: false)
     check("final still post-process when only-on-final", PostProcessor.process(fin, settings: settings), " in the lab")
 }

 if Checks.failures > 0 {
    fputs("CheckPhraseRules: \(Checks.failures) failed\n", stderr)
    exit(1)
}

print("CheckPhraseRules passed")
