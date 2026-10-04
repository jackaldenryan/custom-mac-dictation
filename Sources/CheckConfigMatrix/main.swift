import CustomDictationKit
import Foundation

// Configuration-matrix harness: every insertion strategy through the same
// simulated fields, measuring the same properties.
//
// Two properties the user explicitly wants are measured, not just asserted:
//   - showedLive: dictated text appears BEFORE the phrase is finalized
//     (a live partial wrote something visible)
//   - underlined: the live text carries a mark (AX selection highlight or
//     IMK marked text) rather than plain typed characters
// Everything else (final text, flicker, caret, safety) is pass/fail.

struct MatrixScenario {
    var name: String
    var box: FieldBox
    var initialText: String
    var initialLoc: Int?
    var initialLen: Int
    var partials: [String]
    var final: String
    /// Universal want: every strategy should end here. (Underline is
    /// reported as a capability, not a failure: HID cannot underline.)
    var wantFinal: String
    /// Universal want: no strategy should visibly delete-and-retype here.
    var wantNoFlicker: Bool
    /// Universal want: these boxes must stay untouched.
    var wantSkipped: Bool

    init(
        _ name: String,
        _ box: FieldBox,
        initialText: String = "",
        initialLoc: Int? = nil,
        initialLen: Int = 0,
        partials: [String] = [],
        final: String,
        wantFinal: String,
        wantNoFlicker: Bool = true,
        wantSkipped: Bool = false
    ) {
        self.name = name
        self.box = box
        self.initialText = initialText
        self.initialLoc = initialLoc
        self.initialLen = initialLen
        self.partials = partials
        self.final = final
        self.wantFinal = wantFinal
        self.wantNoFlicker = wantNoFlicker
        self.wantSkipped = wantSkipped
    }
}

let scenarios: [MatrixScenario] = [
    MatrixScenario(
        "notes live + underline", .notes,
        partials: ["Hello", "Hello world"], final: "Hello world",
        wantFinal: "Hello world"
    ),
    MatrixScenario(
        "notes revision (prefix grow)", .notes,
        partials: ["This is a tes", "This is a test"], final: "This is a test",
        wantFinal: "This is a test"
    ),
    MatrixScenario(
        "notes live period dropped by final", .notes,
        partials: ["This is a test."], final: "This is a test",
        wantFinal: "This is a test"
    ),
    MatrixScenario(
        "slack live (no AX coverage)", .slack,
        partials: ["Hey", "Hey team"], final: "Hey team",
        wantFinal: "Hey team", wantNoFlicker: false
    ),
    MatrixScenario(
        "slack revision (non-prefix)", .slack,
        partials: ["reciept", "receipt"], final: "receipt",
        wantFinal: "receipt"
    ),
    MatrixScenario(
        "notes overwrite selection", .notes,
        initialText: "Hello world", initialLoc: 6, initialLen: 5,
        final: "there", wantFinal: "Hello there"
    ),
    MatrixScenario(
        "slack overwrite selection", .slack,
        initialText: "Message Claude", initialLoc: 8, initialLen: 6,
        final: "Jack", wantFinal: "Message Jack"
    ),
    MatrixScenario(
        "opencode mid-caret insert", .openCode,
        initialText: "aa bb", initialLoc: 2,
        partials: ["XX"], final: "XX",
        wantFinal: "aaXX bb"
    ),
    MatrixScenario(
        "chrome url live", .chromeURL,
        partials: ["apple", "apple.com"], final: "apple.com",
        wantFinal: "apple.com"
    ),
    MatrixScenario(
        "finder safety (must skip)", .finder,
        partials: ["hello"], final: "hello",
        wantFinal: "", wantNoFlicker: true, wantSkipped: true
    ),
    MatrixScenario(
        "notes-sidebar safety (must skip)", .notesSidebar,
        initialText: "All iCloud", initialLoc: 0,
        partials: ["Hello", "Hello world"], final: "Hello world",
        wantFinal: "All iCloud", wantSkipped: true
    ),
    MatrixScenario(
        "cursor-stub safety (must skip)", .cursorStub,
        initialText: "code", initialLoc: 4,
        partials: ["Hello", "Hello world"], final: "Hello world",
        wantFinal: "code", wantSkipped: true
    ),
]

struct Run {
    var finalOK: Bool
    var flickered: Bool
    var flickerOK: Bool
    var skipOK: Bool
    var showedLive: Bool
    var underlined: Bool
    var pathOnPartial: String
    var finalText: String
    var keystrokes: Int
}

func run(_ s: MatrixScenario, _ config: InsertConfig) -> Run {
    let field = SimulatedField(box: s.box, text: s.initialText, loc: s.initialLoc, len: s.initialLen)
    let before = field.text
    var showedLive = false
    var underlined = false
    var pathOnPartial = "-"
    if let first = s.partials.first {
        // Observe the FIRST partial: did anything appear, and is it marked?
        config.apply(shaped: first, keepSelected: true, to: field)
        showedLive = !field.displayed.isEmpty
        underlined = field.len > 0 && (field.lastPath == .ax || field.lastPath == .imk)
        pathOnPartial = field.lastPath.rawValue
        for p in s.partials.dropFirst() {
            config.apply(shaped: p, keepSelected: true, to: field)
        }
    }
    config.apply(shaped: s.final, keepSelected: false, to: field)
    field.finishIfNeeded()
    let finalOK = field.text == s.wantFinal
    let flickerOK = !s.wantNoFlicker || !field.flickered
    let skipOK: Bool
    if s.wantSkipped {
        skipOK = field.text == before && field.text == s.wantFinal
    } else {
        skipOK = true
    }
    return Run(
        finalOK: finalOK, flickered: field.flickered, flickerOK: flickerOK, skipOK: skipOK,
        showedLive: showedLive, underlined: underlined,
        pathOnPartial: pathOnPartial, finalText: field.text,
        keystrokes: field.insertedUnits + field.deletedUnits
    )
}

let configs = InsertConfig.all
var totals: [String: (final: Int, flicker: Int, skip: Int, live: Int, under: Int, keys: Int)] = [:]
for c in configs { totals[c.id] = (0, 0, 0, 0, 0, 0) }

print("config matrix: \(scenarios.count) scenarios x \(configs.count) strategies (shaped input, no post-process)")
print("")
for s in scenarios {
    print("### \(s.name) [\(s.box.rawValue)] want=\(String(reflecting: s.wantFinal))")
    for c in configs {
        let r = run(s, c)
        var t = totals[c.id]!
        if r.finalOK { t.final += 1 }
        if r.flickerOK { t.flicker += 1 }
        if r.skipOK { t.skip += 1 }
        if r.showedLive { t.live += 1 }
        if r.underlined { t.under += 1 }
        t.keys += r.keystrokes
        totals[c.id] = t
        let ok = (r.finalOK && r.flickerOK && r.skipOK) ? "ok  " : "FAIL"
        print("  \(ok) \(c.id.padding(toLength: 13, withPad: " ", startingAt: 0)) final=\(r.finalOK ? "y" : "N") flicker=\(r.flickered ? "YES" : "no") live=\(r.showedLive ? "y" : "-") under=\(r.underlined ? "y" : "-") path=\(r.pathOnPartial) keys=\(r.keystrokes) got=\(String(reflecting: r.finalText))")
    }
}

print("")
print("=== totals (n=\(scenarios.count)) ===")
for c in configs {
    let t = totals[c.id]!
    print("\(c.id.padding(toLength: 13, withPad: " ", startingAt: 0)) final-correct \(t.final)/\(scenarios.count)  no-flicker \(t.flicker)/\(scenarios.count)  safety \(t.skip)/\(scenarios.count)  live-shown \(t.live)/\(scenarios.count)  underlined \(t.under)/\(scenarios.count)  keystrokes \(t.keys) (HID path only; AX/IMK are atomic)")
}
print("")
print("=== static trade-offs ===")
for c in configs {
    let t = c.tradeoffs
    print("- \(c.title)")
    print("  ax-permission=\(t.requiresAccessibilityPermission ? "yes" : "no") input-source-install+select=\(t.requiresInputSourceInstallAndSelect ? "YES (friction)" : "no") macOS26-classic-IMK-listed=\(t.macOS26ClassicIMKListed ? "n/a" : "NO (blocker)") clicks/keys-still-need-AX=\(t.stillNeedsAXForClicksAndKeys ? "yes" : "no")")
    print("  coverage: \(t.coverage)")
    print("  underline: \(t.underline)")
}
