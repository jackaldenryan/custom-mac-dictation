import Foundation

public enum CommandMatch: String, Codable, Sendable {
    case exact
    case prefix
    case keyPressGrammar
}

public enum CommandWhen: String, Codable, Sendable {
    case always
    case listening
}

public enum CommandAction: String, Codable, Sendable {
    case startListening
    case stopListening
    case keyPressGrammar
    case openApp
    case quitApp
    case quitFrontmost
    case capitalize
    case uppercase
    case lowercase
    case pasteText
    case shortcut
    case openFile
}

public struct CommandSpec: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var enabled: Bool
    public var builtin: Bool
    public var phrases: [String]
    public var match: CommandMatch
    public var prefix: String?
    public var `when`: CommandWhen
    public var priority: Int
    public var action: CommandAction
    public var pasteText: String?
    public var keyCode: Int?
    public var modifierFlags: UInt64?
    public var fileBookmark: Data?
    public var filePath: String?
    public var scopeBundleID: String?

    enum CodingKeys: String, CodingKey {
        case id, enabled, builtin, phrases, match, prefix, `when`, priority, action
        case pasteText, keyCode, modifierFlags, fileBookmark, filePath, scopeBundleID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        builtin = try c.decodeIfPresent(Bool.self, forKey: .builtin) ?? false
        phrases = try c.decodeIfPresent([String].self, forKey: .phrases) ?? []
        match = try c.decodeIfPresent(CommandMatch.self, forKey: .match) ?? .exact
        prefix = try c.decodeIfPresent(String.self, forKey: .prefix)
        `when` = try c.decodeIfPresent(CommandWhen.self, forKey: .when) ?? .listening
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 100
        if let action = try c.decodeIfPresent(CommandAction.self, forKey: .action) {
            self.action = action
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.action,
                .init(codingPath: c.codingPath, debugDescription: "action is required")
            )
        }
        pasteText = try c.decodeIfPresent(String.self, forKey: .pasteText)
        keyCode = try c.decodeIfPresent(Int.self, forKey: .keyCode)
        modifierFlags = try c.decodeIfPresent(UInt64.self, forKey: .modifierFlags)
        fileBookmark = try c.decodeIfPresent(Data.self, forKey: .fileBookmark)
        filePath = try c.decodeIfPresent(String.self, forKey: .filePath)
        scopeBundleID = try c.decodeIfPresent(String.self, forKey: .scopeBundleID)
    }

    public init(
        id: String,
        enabled: Bool = true,
        builtin: Bool = false,
        phrases: [String] = [],
        match: CommandMatch = .exact,
        prefix: String? = nil,
        when: CommandWhen = .listening,
        priority: Int = 100,
        action: CommandAction,
        pasteText: String? = nil,
        keyCode: Int? = nil,
        modifierFlags: UInt64? = nil,
        fileBookmark: Data? = nil,
        filePath: String? = nil,
        scopeBundleID: String? = nil
    ) {
        self.id = id
        self.enabled = enabled
        self.builtin = builtin
        self.phrases = phrases
        self.match = match
        self.prefix = prefix
        self.when = when
        self.priority = priority
        self.action = action
        self.pasteText = pasteText
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.fileBookmark = fileBookmark
        self.filePath = filePath
        self.scopeBundleID = scopeBundleID
    }

    public init(_ imported: ImportedCommand) {
        let action: CommandAction
        switch imported.kind {
        case .pasteText: action = .pasteText
        case .shortcut: action = .shortcut
        case .openFile: action = .openFile
        }
        self.init(
            id: imported.id,
            enabled: imported.enabled,
            builtin: false,
            phrases: imported.phrases,
            match: .exact,
            when: .listening,
            priority: 100,
            action: action,
            pasteText: imported.pasteText,
            keyCode: imported.keyCode,
            modifierFlags: imported.modifierFlags,
            fileBookmark: imported.fileBookmark,
            filePath: imported.filePath,
            scopeBundleID: imported.scopeBundleID
        )
    }

    public var title: String {
        if let first = phrases.first, !first.isEmpty { return first }
        if let prefix { return prefix.trimmingCharacters(in: .whitespaces) }
        return id
    }

    public var actionTitle: String {
        switch action {
        case .startListening: return "Start listening"
        case .stopListening: return "Stop listening"
        case .keyPressGrammar: return "Press key"
        case .openApp: return "Open app"
        case .quitApp: return "Quit app"
        case .quitFrontmost: return "Quit frontmost"
        case .capitalize: return "Capitalize"
        case .uppercase: return "Uppercase"
        case .lowercase: return "Lowercase"
        case .pasteText: return "Paste text"
        case .shortcut: return "Shortcut"
        case .openFile: return "Open file"
        }
    }

    public static let builtIns: [CommandSpec] = [
        CommandSpec(
            id: "builtin.start-listening",
            builtin: true,
            phrases: ["start listening dictation", "start listening mac"],
            match: .exact,
            when: .always,
            priority: 0,
            action: .startListening
        ),
        CommandSpec(
            id: "builtin.stop-listening",
            builtin: true,
            phrases: ["stop listening dictation", "stop listening mac"],
            match: .exact,
            when: .always,
            priority: 1,
            action: .stopListening
        ),
        CommandSpec(
            id: "builtin.press",
            builtin: true,
            phrases: ["press"],
            match: .keyPressGrammar,
            when: .listening,
            priority: 190,
            action: .keyPressGrammar
        ),
        CommandSpec(
            id: "builtin.open-app",
            builtin: true,
            phrases: ["open"],
            match: .prefix,
            prefix: "open ",
            when: .listening,
            priority: 200,
            action: .openApp
        ),
        CommandSpec(
            id: "builtin.quit-frontmost",
            builtin: true,
            phrases: ["quit application", "quit the application", "quit app"],
            match: .exact,
            when: .listening,
            priority: 210,
            action: .quitFrontmost
        ),
        CommandSpec(
            id: "builtin.quit-app",
            builtin: true,
            phrases: ["quit"],
            match: .prefix,
            prefix: "quit ",
            when: .listening,
            priority: 220,
            action: .quitApp
        ),
        CommandSpec(
            id: "builtin.capitalize",
            builtin: true,
            phrases: ["capitalize that", "capital that", "capitalise that"],
            match: .exact,
            when: .listening,
            priority: 230,
            action: .capitalize
        ),
        CommandSpec(
            id: "builtin.uppercase",
            builtin: true,
            phrases: ["uppercase that", "upper case that", "all caps that"],
            match: .exact,
            when: .listening,
            priority: 231,
            action: .uppercase
        ),
        CommandSpec(
            id: "builtin.lowercase",
            builtin: true,
            phrases: ["lowercase that", "lower case that", "all lowercase that"],
            match: .exact,
            when: .listening,
            priority: 232,
            action: .lowercase
        )
    ]
}
