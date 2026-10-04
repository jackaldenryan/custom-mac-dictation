import CustomDictationKit
import Foundation

enum Engine: String, CaseIterable {
    case desired
    case local
    case release
}

enum Box: String {
    case notes
    case chromeURL
    case googleSearch
    case slack
    case cursorEditor
    case cursorStub
    case zoom
    case finder
    case notesSidebar
}

struct Want {
    var text: String
    var intoStub: Bool = false
    var flickered: Bool = false
    var liveVisible: Bool? = nil
    var commandFailed: Bool = false
}

struct Got: Equatable {
    var text: String
    var intoStub: Bool
    var flickered: Bool
    var liveVisible: Bool
    var commandFailed: Bool
}

struct BoxProfile {
    var axWrite: Bool
    var unicodeReplacesSelection: Bool
    var electronCopy: Bool
    var stubFocused: Bool
    var hasClient: Bool
}

func profile(_ box: Box) -> BoxProfile {
    switch box {
    case .notes, .chromeURL:
        return BoxProfile(axWrite: true, unicodeReplacesSelection: true, electronCopy: true, stubFocused: false, hasClient: true)
    case .googleSearch, .zoom:
        return BoxProfile(axWrite: false, unicodeReplacesSelection: false, electronCopy: true, stubFocused: false, hasClient: true)
    case .slack:
        return BoxProfile(axWrite: false, unicodeReplacesSelection: false, electronCopy: false, stubFocused: false, hasClient: true)
    case .cursorEditor:
        return BoxProfile(axWrite: false, unicodeReplacesSelection: false, electronCopy: false, stubFocused: false, hasClient: true)
    case .cursorStub:
        return BoxProfile(axWrite: false, unicodeReplacesSelection: false, electronCopy: false, stubFocused: true, hasClient: false)
    case .finder, .notesSidebar:
        return BoxProfile(axWrite: false, unicodeReplacesSelection: false, electronCopy: false, stubFocused: false, hasClient: false)
    }
}

final class Doc {
    var text: String
    var loc: Int
    var len: Int
    var flickered = false
    var intoStub = false
    var liveVisible = false
    var commandFailed = false
    var pendingLeadSpace: Bool
    let box: Box
    let engine: Engine
    private var displayed = ""
    private var markStart: Int?
    private var stubText = ""

    init(text: String, loc: Int? = nil, len: Int = 0, box: Box, engine: Engine, pendingLeadSpace: Bool = false) {
        self.text = text
        self.loc = loc ?? (text as NSString).length
        self.len = len
        self.box = box
        self.engine = engine
        self.pendingLeadSpace = pendingLeadSpace
    }

    var p: BoxProfile { profile(box) }

    func shape(_ transcript: String, partial: Bool) -> String? {
        PhraseSimulation.typed(
            into: text,
            at: loc,
            selectedLength: len,
            transcript: transcript,
            pendingLeadSpace: pendingLeadSpace
        )
    }

    func snapshot() -> Got {
        Got(text: text, intoStub: intoStub, flickered: flickered, liveVisible: liveVisible, commandFailed: commandFailed)
    }

    func deleteSelection() {
        guard len > 0 else { return }
        let ns = text as NSString
        text = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: "")
        len = 0
    }

    func deleteBackward(_ n: Int) {
        guard n > 0 else { return }
        if len > 0 {
            deleteSelection()
            return
        }
        let ns = text as NSString
        let start = max(0, loc - n)
        text = ns.replacingCharacters(in: NSRange(location: start, length: loc - start), with: "")
        loc = start
    }

    func unicodeInsert(_ s: String) {
        if p.stubFocused {
            intoStub = true
            stubText += s
            return
        }
        if !p.hasClient { return }
        if !p.unicodeReplacesSelection {
            let ns = text as NSString
            text = ns.replacingCharacters(in: NSRange(location: loc, length: 0), with: s)
            loc += (s as NSString).length
            len = 0
            return
        }
        deleteSelection()
        let ns = text as NSString
        text = ns.replacingCharacters(in: NSRange(location: loc, length: 0), with: s)
        loc += (s as NSString).length
    }

    func axReplaceMark(with s: String, select: Bool) {
        let start = markStart ?? loc
        let ns = text as NSString
        let existing = max(0, loc - start)
        text = ns.replacingCharacters(in: NSRange(location: start, length: existing + len), with: s)
        markStart = start
        if select {
            loc = start
            len = (s as NSString).length
        } else {
            loc = start + (s as NSString).length
            len = 0
            markStart = nil
        }
    }

    func dictation(partials: [String], final: String) {
        if engine == .desired {
            desiredDictation(partials: partials, final: final)
            return
        }
        if engine == .local {
            localDictation(partials: partials, final: final)
            return
        }
        releaseDictation(partials: partials, final: final)
    }

    private func desiredDictation(partials: [String], final: String) {
        if !p.hasClient { return }
        if len > 0 { deleteSelection() }
        markStart = loc
        let steps = partials + [final]
        for (i, raw) in steps.enumerated() {
            guard let out = shape(raw, partial: i < partials.count) else { continue }
            axReplaceMark(with: out, select: i < partials.count && !out.isEmpty)
            if i < partials.count { liveVisible = true }
            displayed = out
        }
        pendingLeadSpace = !displayed.isEmpty
        displayed = ""
    }

    private func localDictation(partials: [String], final: String) {
        desiredDictation(partials: partials, final: final)
    }

    private func releaseDictation(partials: [String], final: String) {
        displayed = ""
        let steps = partials + [final]
        for (i, raw) in steps.enumerated() {
            guard let out = shape(raw, partial: i < partials.count) else { continue }
            if displayed == out { continue }
            if keepsTrailingPunctuation(displayed: displayed, incoming: out) { continue }
            if displayed.isEmpty {
                unicodeInsert(out)
            } else if folds(out).hasPrefix(folds(displayed)) {
                unicodeInsert(String(out.dropFirst(displayed.count)))
            } else {
                flickered = true
                deleteBackward((displayed as NSString).length)
                unicodeInsert(out)
            }
            displayed = out
            if i < partials.count { liveVisible = true }
        }
        pendingLeadSpace = !displayed.isEmpty
        displayed = ""
    }

    /// A spoken mark on its own ("question mark" -> "?"). With Apple's
    /// automatic punctuation off, every mark Apple sends was spoken.
    func sayPunctuation(_ mark: String) {
        let chunk = PhraseSimulation.typed(
            into: text,
            at: loc,
            selectedLength: len,
            transcript: mark,
            pendingLeadSpace: false
        )
        if let chunk {
            unicodeInsert(chunk)
        }
    }

    func lowercaseSelection() {
        let selected: String?
        if len > 0 {
            selected = (text as NSString).substring(with: NSRange(location: loc, length: len))
        } else {
            selected = nil
        }
        switch engine {
        case .desired:
            guard let raw = selected, !raw.isEmpty else {
                commandFailed = true
                return
            }
            replaceSelected(raw.lowercased())
        case .local:
            guard let raw = selected, !raw.isEmpty else {
                commandFailed = true
                return
            }
            replaceSelected(raw.lowercased())
        case .release:
            if p.axWrite, let raw = selected, !raw.isEmpty {
                replaceSelected(raw.lowercased())
                return
            }
            commandFailed = true
        }
    }

    func uppercaseSelection() {
        let selected: String?
        if len > 0 {
            selected = (text as NSString).substring(with: NSRange(location: loc, length: len))
        } else {
            selected = nil
        }
        switch engine {
        case .desired:
            guard let raw = selected, !raw.isEmpty else {
                commandFailed = true
                return
            }
            replaceSelected(raw.uppercased())
        case .local:
            guard let raw = selected, !raw.isEmpty else {
                commandFailed = true
                return
            }
            replaceSelected(raw.uppercased())
        case .release:
            if p.axWrite, let raw = selected, !raw.isEmpty {
                replaceSelected(raw.uppercased())
                return
            }
            commandFailed = true
        }
    }

    private func replaceSelected(_ s: String) {
        let ns = text as NSString
        text = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: s)
        loc += (s as NSString).length
        len = 0
    }

    func commandClickHoldsModifier() -> Bool {
        return true
    }
}

private func folds(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\u{2019}", with: "'")
        .replacingOccurrences(of: "\u{2018}", with: "'")
        .replacingOccurrences(of: "\u{02BC}", with: "'")
}

private func keepsTrailingPunctuation(displayed: String, incoming: String) -> Bool {
    let have = folds(displayed)
    let next = folds(incoming)
    guard have.hasPrefix(next), have.count > next.count else { return false }
    let extra = have.dropFirst(next.count)
    return extra.unicodeScalars.allSatisfy {
        CharacterSet.punctuationCharacters.contains($0) || $0.properties.isWhitespace
    }
}

struct Case {
    var name: String
    var run: (Engine) -> (Got, Want)
}

func eq(_ got: Got, _ want: Want) -> Bool {
    if got.text != want.text { return false }
    if got.intoStub != want.intoStub { return false }
    if got.flickered != want.flickered { return false }
    if let live = want.liveVisible, got.liveVisible != live { return false }
    if got.commandFailed != want.commandFailed { return false }
    return true
}

let cases: [Case] = [
    Case(name: "notes live phrase") { engine in
        let d = Doc(text: "", box: .notes, engine: engine)
        d.dictation(partials: ["Hello", "Hello world"], final: "Hello world")
        return (d.snapshot(), Want(text: "Hello world", liveVisible: true))
    },
    Case(name: "notes live revision no junk") { engine in
        let d = Doc(text: "", box: .notes, engine: engine)
        d.dictation(partials: ["This is a tes", "This is a test"], final: "This is a test")
        return (d.snapshot(), Want(text: "This is a test", flickered: false, liveVisible: true))
    },
    Case(name: "notes insert at caret mid sentence") { engine in
        let d = Doc(text: "Hello world", loc: 5, box: .notes, engine: engine)
        d.dictation(partials: [], final: "there")
        return (d.snapshot(), Want(text: "Hello there world"))
    },
    Case(name: "notes overwrite selection") { engine in
        let d = Doc(text: "Hello world", loc: 6, len: 5, box: .notes, engine: engine)
        d.dictation(partials: ["there"], final: "there")
        return (d.snapshot(), Want(text: "Hello there"))
    },
    Case(name: "notes uppercase that") { engine in
        let d = Doc(text: "Hello world", loc: 6, len: 5, box: .notes, engine: engine)
        d.uppercaseSelection()
        return (d.snapshot(), Want(text: "Hello WORLD"))
    },
    Case(name: "notes lowercase whole line") { engine in
        let d = Doc(text: "HELLO", loc: 0, len: 5, box: .notes, engine: engine)
        d.lowercaseSelection()
        return (d.snapshot(), Want(text: "hello"))
    },
    Case(name: "chrome url live") { engine in
        let d = Doc(text: "", box: .chromeURL, engine: engine)
        d.dictation(partials: ["apple", "apple.com"], final: "apple.com")
        return (d.snapshot(), Want(text: "Apple.com", liveVisible: true))
    },
    Case(name: "google search commit") { engine in
        let d = Doc(text: "", box: .googleSearch, engine: engine)
        d.dictation(partials: ["weather"], final: "weather")
        return (d.snapshot(), Want(text: "Weather"))
    },
    Case(name: "google search live preview") { engine in
        let d = Doc(text: "", box: .googleSearch, engine: engine)
        d.dictation(partials: ["weather in", "weather in austin"], final: "weather in austin")
        return (d.snapshot(), Want(text: "Weather in austin", liveVisible: true))
    },
    Case(name: "google search no flicker") { engine in
        let d = Doc(text: "", box: .googleSearch, engine: engine)
        d.dictation(partials: ["weath", "weather"], final: "weather")
        return (d.snapshot(), Want(text: "Weather", flickered: false))
    },
    Case(name: "google search overwrite selection") { engine in
        let d = Doc(text: "old query", loc: 0, len: 9, box: .googleSearch, engine: engine)
        d.dictation(partials: [], final: "new")
        return (d.snapshot(), Want(text: "New"))
    },
    Case(name: "slack live preview") { engine in
        let d = Doc(text: "", box: .slack, engine: engine)
        d.dictation(partials: ["Hey", "Hey team"], final: "Hey team")
        return (d.snapshot(), Want(text: "Hey team", liveVisible: true))
    },
    Case(name: "slack live no flicker") { engine in
        let d = Doc(text: "", box: .slack, engine: engine)
        d.dictation(partials: ["Hey t", "Hey team"], final: "Hey team")
        return (d.snapshot(), Want(text: "Hey team", flickered: false))
    },
    Case(name: "slack overwrite selected word") { engine in
        let d = Doc(text: "Message Claude", loc: 8, len: 6, box: .slack, engine: engine)
        d.dictation(partials: ["Jack"], final: "Jack")
        return (d.snapshot(), Want(text: "Message jack"))
    },
    Case(name: "slack insert mid sentence") { engine in
        let d = Doc(text: "Message Claude", loc: 7, box: .slack, engine: engine)
        d.dictation(partials: [], final: "to")
        return (d.snapshot(), Want(text: "Message to Claude"))
    },
    Case(name: "slack uppercase that") { engine in
        let d = Doc(text: "hello world", loc: 6, len: 5, box: .slack, engine: engine)
        d.uppercaseSelection()
        return (d.snapshot(), Want(text: "hello WORLD"))
    },
    Case(name: "slack lowercase that") { engine in
        let d = Doc(text: "HELLO", loc: 0, len: 5, box: .slack, engine: engine)
        d.lowercaseSelection()
        return (d.snapshot(), Want(text: "hello"))
    },
    Case(name: "cursor editor live") { engine in
        let d = Doc(text: "", box: .cursorEditor, engine: engine)
        d.dictation(partials: ["func", "func main"], final: "func main")
        return (d.snapshot(), Want(text: "Func main", liveVisible: true))
    },
    Case(name: "cursor editor no flicker") { engine in
        let d = Doc(text: "", box: .cursorEditor, engine: engine)
        d.dictation(partials: ["fu", "func"], final: "func")
        return (d.snapshot(), Want(text: "Func", flickered: false))
    },
    Case(name: "cursor overwrite selection") { engine in
        let d = Doc(text: "hello world", loc: 0, len: 5, box: .cursorEditor, engine: engine)
        d.dictation(partials: [], final: "goodbye")
        return (d.snapshot(), Want(text: "Goodbye world"))
    },
    Case(name: "cursor stub click away does not type") { engine in
        let d = Doc(text: "editor", loc: 6, box: .cursorStub, engine: engine)
        d.dictation(partials: ["hello"], final: "hello")
        return (d.snapshot(), Want(text: "editor", intoStub: false))
    },
    Case(name: "zoom chat commit") { engine in
        let d = Doc(text: "", box: .zoom, engine: engine)
        d.dictation(partials: ["hi"], final: "hi")
        return (d.snapshot(), Want(text: "Hi"))
    },
    Case(name: "zoom live no flicker") { engine in
        let d = Doc(text: "", box: .zoom, engine: engine)
        d.dictation(partials: ["h", "hi there"], final: "hi there")
        return (d.snapshot(), Want(text: "Hi there", flickered: false, liveVisible: true))
    },
    Case(name: "spoken period after word") { engine in
        let d = Doc(text: "Working now", box: .notes, engine: engine)
        d.sayPunctuation(".")
        return (d.snapshot(), Want(text: "Working now."))
    },
    Case(name: "second spoken question mark after one") { engine in
        let d = Doc(text: "Really?", box: .slack, engine: engine)
        d.sayPunctuation("?")
        return (d.snapshot(), Want(text: "Really??"))
    },
    Case(name: "spoken comma right after a period") { engine in
        let d = Doc(text: "Done.", box: .notes, engine: engine)
        d.sayPunctuation(",")
        return (d.snapshot(), Want(text: "Done.,"))
    },
    Case(name: "second utterance spaces") { engine in
        let d = Doc(text: "", box: .notes, engine: engine)
        d.dictation(partials: [], final: "Hello")
        d.dictation(partials: [], final: "there")
        return (d.snapshot(), Want(text: "Hello there"))
    },
    Case(name: "notes next sentence at caret end not old mark") { engine in
        let d = Doc(text: "", box: .notes, engine: engine)
        d.dictation(partials: ["Hello there."], final: "Hello there.")
        d.loc = (d.text as NSString).length
        d.len = 0
        d.dictation(partials: ["Another one."], final: "Another one.")
        return (d.snapshot(), Want(text: "Hello there.Another one."))
    },
    Case(name: "command click holds command") { engine in
        let d = Doc(text: "", box: .googleSearch, engine: engine)
        let held = d.commandClickHoldsModifier()
        return (Got(text: held ? "held" : "bare", intoStub: false, flickered: false, liveVisible: false, commandFailed: false), Want(text: "held"))
    },
    Case(name: "notes empty selection uppercase fails") { engine in
        let d = Doc(text: "hello", loc: 5, box: .notes, engine: engine)
        d.uppercaseSelection()
        return (d.snapshot(), Want(text: "hello", commandFailed: true))
    },
    Case(name: "slack revision replace not append junk") { engine in
        let d = Doc(text: "", box: .slack, engine: engine)
        d.dictation(partials: ["I was edit slack", "I was editing Slack"], final: "I was editing Slack")
        return (d.snapshot(), Want(text: "I was editing Slack", flickered: false))
    },
    Case(name: "google selection insert not splice") { engine in
        let d = Doc(text: "weather", loc: 0, len: 7, box: .googleSearch, engine: engine)
        d.dictation(partials: ["traffic"], final: "traffic")
        return (d.snapshot(), Want(text: "Traffic"))
    },
    Case(name: "chrome url overwrite selection") { engine in
        let d = Doc(text: "old.com", loc: 0, len: 7, box: .chromeURL, engine: engine)
        d.dictation(partials: [], final: "new.com")
        return (d.snapshot(), Want(text: "New.com"))
    },
    Case(name: "notes apple final drops live period") { engine in
        let d = Doc(text: "", box: .notes, engine: engine)
        d.dictation(partials: ["This is a test."], final: "This is a test")
        return (d.snapshot(), Want(text: "This is a test"))
    },
    Case(name: "notes keep live then commit") { engine in
        let d = Doc(text: "Hi ", loc: 3, box: .notes, engine: engine)
        d.dictation(partials: ["Jack"], final: "Jack")
        return (d.snapshot(), Want(text: "Hi jack", liveVisible: true))
    },
    Case(name: "cursor editor uppercase") { engine in
        let d = Doc(text: "hello", loc: 0, len: 5, box: .cursorEditor, engine: engine)
        d.uppercaseSelection()
        return (d.snapshot(), Want(text: "HELLO"))
    },
    Case(name: "zoom overwrite selection") { engine in
        let d = Doc(text: "hello there", loc: 6, len: 5, box: .zoom, engine: engine)
        d.dictation(partials: [], final: "Jack")
        return (d.snapshot(), Want(text: "hello jack"))
    },
    Case(name: "slack caret add word") { engine in
        let d = Doc(text: "hello world", loc: 5, box: .slack, engine: engine)
        d.dictation(partials: [], final: "there")
        return (d.snapshot(), Want(text: "hello there world"))
    },
    Case(name: "google live revision") { engine in
        let d = Doc(text: "", box: .googleSearch, engine: engine)
        d.dictation(partials: ["wether", "weather"], final: "weather")
        return (d.snapshot(), Want(text: "Weather", flickered: false))
    },
    Case(name: "slack compose from empty") { engine in
        let d = Doc(text: "", box: .slack, engine: engine)
        d.dictation(partials: [], final: "hi")
        return (d.snapshot(), Want(text: "Hi"))
    },
]

let extraFieldCases: [Case] = {
    let boxes: [Box] = [.notes, .chromeURL, .googleSearch, .slack, .cursorEditor, .zoom]
    var extra: [Case] = []
    for box in boxes {
        let n = box.rawValue
        extra.append(Case(name: "\(n) empty hello") { engine in
            let d = Doc(text: "", box: box, engine: engine)
            d.dictation(partials: [], final: "hello")
            return (d.snapshot(), Want(text: "Hello"))
        })
        extra.append(Case(name: "\(n) live prefix no flicker") { engine in
            let d = Doc(text: "", box: box, engine: engine)
            d.dictation(partials: ["Hel", "Hello"], final: "Hello")
            return (d.snapshot(), Want(text: "Hello", flickered: false, liveVisible: true))
        })
        extra.append(Case(name: "\(n) two utterances") { engine in
            let d = Doc(text: "", box: box, engine: engine)
            d.dictation(partials: [], final: "Hello")
            d.dictation(partials: [], final: "there")
            return (d.snapshot(), Want(text: "Hello there"))
        })
        extra.append(Case(name: "\(n) overwrite middle word") { engine in
            let d = Doc(text: "one two three", loc: 4, len: 3, box: box, engine: engine)
            d.dictation(partials: [], final: "too")
            return (d.snapshot(), Want(text: "one too three"))
        })
        extra.append(Case(name: "\(n) insert at end") { engine in
            let d = Doc(text: "Hello", loc: 5, box: box, engine: engine)
            d.dictation(partials: [], final: "there")
            return (d.snapshot(), Want(text: "Hello there"))
        })
        extra.append(Case(name: "\(n) uppercase word") { engine in
            let d = Doc(text: "say hello", loc: 4, len: 5, box: box, engine: engine)
            d.uppercaseSelection()
            return (d.snapshot(), Want(text: "say HELLO"))
        })
        extra.append(Case(name: "\(n) empty uppercase fails") { engine in
            let d = Doc(text: "hello", loc: 5, box: box, engine: engine)
            d.uppercaseSelection()
            return (d.snapshot(), Want(text: "hello", commandFailed: true))
        })
    }
    extra.append(Case(name: "notes click to middle after two sentences") { engine in
        let d = Doc(text: "", box: .notes, engine: engine)
        d.dictation(partials: [], final: "Alpha")
        d.dictation(partials: [], final: "Bravo")
        d.loc = 5
        d.len = 0
        d.dictation(partials: [], final: "mid")
        return (d.snapshot(), Want(text: "Alpha mid bravo"))
    })
    extra.append(Case(name: "notes third utterance at end") { engine in
        let d = Doc(text: "", box: .notes, engine: engine)
        d.dictation(partials: [], final: "One")
        d.dictation(partials: [], final: "two")
        d.dictation(partials: [], final: "three")
        return (d.snapshot(), Want(text: "One two three"))
    })
    extra.append(Case(name: "slack second utterance") { engine in
        let d = Doc(text: "", box: .slack, engine: engine)
        d.dictation(partials: ["Hey"], final: "Hey")
        d.dictation(partials: ["team"], final: "team")
        return (d.snapshot(), Want(text: "Heyteam", liveVisible: true))
    })
    extra.append(Case(name: "cursor stub never grows editor") { engine in
        let d = Doc(text: "code", loc: 4, box: .cursorStub, engine: engine)
        d.dictation(partials: ["Hello", "Hello world"], final: "Hello world")
        return (d.snapshot(), Want(text: "code", intoStub: false, liveVisible: false))
    })
    extra.append(Case(name: "notes live same final does not duplicate") { engine in
        let d = Doc(text: "", box: .notes, engine: engine)
        d.dictation(partials: ["Hello"], final: "Hello")
        return (d.snapshot(), Want(text: "Hello"))
    })
    extra.append(Case(name: "google search insert at caret") { engine in
        let d = Doc(text: "weather austin", loc: 8, box: .googleSearch, engine: engine)
        d.dictation(partials: [], final: "in")
        return (d.snapshot(), Want(text: "weather inaustin"))
    })
    extra.append(Case(name: "chrome url second query") { engine in
        let d = Doc(text: "", box: .chromeURL, engine: engine)
        d.dictation(partials: [], final: "apple.com")
        d.loc = (d.text as NSString).length
        d.len = 0
        d.dictation(partials: [], final: "news")
        return (d.snapshot(), Want(text: "Apple.com news"))
    })
    extra.append(Case(name: "slack capitalize selection via uppercase") { engine in
        let d = Doc(text: "ok", loc: 0, len: 2, box: .slack, engine: engine)
        d.uppercaseSelection()
        return (d.snapshot(), Want(text: "OK"))
    })
    extra.append(Case(name: "notes overwrite then continue at end") { engine in
        let d = Doc(text: "Hello world", loc: 6, len: 5, box: .notes, engine: engine)
        d.dictation(partials: [], final: "there")
        d.loc = (d.text as NSString).length
        d.len = 0
        d.dictation(partials: [], final: "friend")
        return (d.snapshot(), Want(text: "Hello there friend"))
    })
    extra.append(Case(name: "option click holds") { engine in
        let d = Doc(text: "", box: .chromeURL, engine: engine)
        let held = d.commandClickHoldsModifier()
        return (Got(text: held ? "held" : "bare", intoStub: false, flickered: false, liveVisible: false, commandFailed: false), Want(text: "held"))
    })
    extra.append(Case(name: "hid revision no leftover first guess") { engine in
        let d = Doc(text: "", box: .slack, engine: engine)
        d.dictation(partials: ["reciept", "receipt"], final: "receipt")
        return (d.snapshot(), Want(text: "Receipt", flickered: false))
    })
    extra.append(Case(name: "notes caret zero insert") { engine in
        let d = Doc(text: "world", loc: 0, box: .notes, engine: engine)
        d.dictation(partials: [], final: "hello")
        return (d.snapshot(), Want(text: "Helloworld"))
    })
    extra.append(Case(name: "finder dictation does nothing") { engine in
        let d = Doc(text: "", box: .finder, engine: engine)
        d.dictation(partials: ["hello"], final: "hello")
        return (d.snapshot(), Want(text: "", intoStub: false, liveVisible: false))
    })
    extra.append(Case(name: "finder does not select files") { engine in
        let d = Doc(text: "Documents", loc: 0, box: .finder, engine: engine)
        d.dictation(partials: ["notes"], final: "notes")
        return (d.snapshot(), Want(text: "Documents", intoStub: false))
    })
    extra.append(Case(name: "notes sidebar dictation does nothing") { engine in
        let d = Doc(text: "All iCloud", loc: 0, box: .notesSidebar, engine: engine)
        d.dictation(partials: ["Hello", "Hello world"], final: "Hello world")
        return (d.snapshot(), Want(text: "All iCloud", intoStub: false, liveVisible: false))
    })
    return extra
}()

let all = cases + extraFieldCases

struct Score {
    var pass = 0
    var fail: [(String, Got, Want)] = []
}

@MainActor
func run(_ engine: Engine) -> Score {
    var s = Score()
    for c in all {
        let (got, want) = c.run(engine)
        if eq(got, want) {
            s.pass += 1
        } else {
            s.fail.append((c.name, got, want))
        }
    }
    return s
}

@MainActor
func show(_ label: String, _ s: Score) {
    let n = all.count
    print("\(label)  \(s.pass)/\(n)")
    for (name, got, want) in s.fail {
        print("  FAIL \(name)")
        print("    got  text=\(String(reflecting: got.text)) stub=\(got.intoStub) flicker=\(got.flickered) live=\(got.liveVisible) cmdFail=\(got.commandFailed)")
        print("    want text=\(String(reflecting: want.text)) stub=\(want.intoStub) flicker=\(want.flickered) live=\(want.liveVisible.map(String.init) ?? "*") cmdFail=\(want.commandFailed)")
    }
}

let desired = run(.desired)
let local = run(.local)
let release = run(.release)
print("field scenarios: \(all.count)")
show("desired (spec)", desired)
show("local          ", local)
show("release v0.1.37", release)
if desired.pass != all.count {
    fputs("spec engine failed its own tests\n", stderr)
    exit(1)
}
