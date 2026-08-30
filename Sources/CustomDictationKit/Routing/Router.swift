import AppKit
import Foundation

public enum RouteResult: Equatable, Sendable {
    case handled
    case typed
    case ignored
    case failed(String)
}

public enum Router {
    public static func handle(
        transcript: String,
        state: ListeningState,
        settings: AppSettings,
        onStartListening: () -> Void,
        onStopListening: () -> Void
    ) -> RouteResult {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = TranscriptNormalizer.normalize(transcript)
        let commands = settings.commands.filter(\.enabled)

        if let command = firstMatch(normalized: normalized, transcript: transcript, commands: commands, when: .always) {
            return run(command, transcript: transcript, normalized: normalized, state: state, settings: settings, onStartListening: onStartListening, onStopListening: onStopListening)
        }
        if state != .listening {
            return .ignored
        }

        let userExact = commands.filter { !$0.builtin && $0.match == .exact && $0.when == .listening }
        if let command = bestExact(normalized: normalized, commands: userExact) {
            LivePhrase.discard()
            return run(command, transcript: transcript, normalized: normalized, state: state, settings: settings, onStartListening: onStartListening, onStopListening: onStopListening)
        }

        let rest = commands.filter { $0.when == .listening && ($0.builtin || $0.match != .exact) }
            .sorted { $0.priority < $1.priority }
        if let command = firstMatch(normalized: normalized, transcript: transcript, commands: rest, when: .listening) {
            LivePhrase.discard()
            return run(command, transcript: transcript, normalized: normalized, state: state, settings: settings, onStartListening: onStartListening, onStopListening: onStopListening)
        }

        guard !trimmed.isEmpty, !TranscriptNormalizer.isLonePunctuation(trimmed) else { return .ignored }
        LivePhrase.commit(trimmed)
        return .typed
    }

    public static func shouldHoldLive(transcript: String, state: ListeningState, settings: AppSettings) -> Bool {
        if state != .listening { return true }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = TranscriptNormalizer.normalize(transcript)
        if normalized.isEmpty { return trimmed.isEmpty }
        return settings.commands.contains { command in
            guard command.enabled else { return false }
            return holds(command, normalized: normalized)
        }
    }

    private static func firstMatch(
        normalized: String,
        transcript: String,
        commands: [CommandSpec],
        when: CommandWhen
    ) -> CommandSpec? {
        commands
            .filter { $0.when == when }
            .sorted { $0.priority < $1.priority }
            .first { matches($0, normalized: normalized, transcript: transcript) }
    }

    private static func bestExact(normalized: String, commands: [CommandSpec]) -> CommandSpec? {
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let matches = commands.filter { command in
            if let scope = command.scopeBundleID, scope != frontID { return false }
            return command.phrases.contains { TranscriptNormalizer.normalize($0) == normalized }
        }
        return matches.max { $0.phrases.joined().count < $1.phrases.joined().count }
    }

    private static func matches(_ command: CommandSpec, normalized: String, transcript: String) -> Bool {
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let scope = command.scopeBundleID, scope != frontID { return false }
        switch command.match {
        case .exact:
            return command.phrases.contains { TranscriptNormalizer.normalize($0) == normalized }
        case .prefix:
            let prefix = command.prefix ?? ""
            return !prefix.isEmpty && normalized.hasPrefix(prefix) && normalized.count > prefix.count
        case .appSlot:
            return command.appArgument(normalized: normalized) != nil
        case .keyPressGrammar:
            return KeyPressGrammar.parse(transcript) != nil
        }
    }

    private static func holds(_ command: CommandSpec, normalized: String) -> Bool {
        switch command.match {
        case .exact:
            return command.phrases.contains { phrase in
                let name = TranscriptNormalizer.normalize(phrase)
                if name == normalized { return true }
                guard name.hasPrefix(normalized), normalized.count >= 3 else { return false }
                let rest = name.dropFirst(normalized.count)
                return rest.first == " " || rest.isEmpty
            }
        case .prefix:
            let prefix = command.prefix ?? ""
            let word = prefix.trimmingCharacters(in: .whitespaces)
            return normalized == word || (!prefix.isEmpty && normalized.hasPrefix(prefix)) || (!word.isEmpty && normalized.hasPrefix(word + " "))
        case .appSlot:
            return command.holdsAppSlot(normalized: normalized)
        case .keyPressGrammar:
            return normalized == "press" || normalized.hasPrefix("press ")
        }
    }

    private static func run(
        _ command: CommandSpec,
        transcript: String,
        normalized: String,
        state: ListeningState,
        settings: AppSettings,
        onStartListening: () -> Void,
        onStopListening: () -> Void
    ) -> RouteResult {
        switch command.action {
        case .startListening:
            LivePhrase.discard()
            if state != .listening { onStartListening() }
            return .handled
        case .stopListening:
            LivePhrase.keepAndUnhighlight()
            if state == .listening { onStopListening() }
            return .handled
        case .keyPressGrammar:
            guard let key = KeyPressGrammar.parse(transcript) else { return .ignored }
            Typist.press(
                keyCode: key.keyCode,
                flags: key.flags,
                character: key.character,
                times: key.times,
                intervalSeconds: settings.keyRepeatDelaySeconds
            )
            return .handled
        case .click:
            Typist.click(
                flags: Typist.cgFlags(from: command.modifierFlags ?? 0),
                right: command.clickButton == "right",
                times: command.clickTimes ?? 1
            )
            return .handled
        case .openApp:
            let name = command.appArgument(normalized: normalized) ?? argument(normalized, prefix: command.prefix ?? "open ")
            do {
                try AppController.open(spokenName: name)
                return .handled
            } catch AppControlError.notFound {
                return .failed("I could not find \(name)")
            } catch {
                return .failed("I could not open \(name)")
            }
        case .quitFrontmost:
            do {
                try AppController.quitFrontmost()
                return .handled
            } catch {
                return .failed("I could not quit that application")
            }
        case .quitApp:
            let name = command.appArgument(normalized: normalized) ?? argument(normalized, prefix: command.prefix ?? "quit ")
            do {
                try AppController.quit(spokenName: name)
                return .handled
            } catch AppControlError.notFound {
                return .failed("I could not find \(name)")
            } catch {
                return .failed("I could not quit \(name)")
            }
        case .capitalize:
            return transform(.capitalize)
        case .uppercase:
            return transform(.uppercase)
        case .lowercase:
            return transform(.lowercase)
        case .shortcut:
            guard let keyCode = command.keyCode else { return .failed("That shortcut is incomplete") }
            Typist.pressShortcut(keyCode: keyCode, modifierFlags: command.modifierFlags ?? 0)
            return .handled
        case .pasteText:
            guard let text = command.pasteText, !text.isEmpty else { return .failed("That paste command is empty") }
            Typist.typeText(text)
            return .handled
        case .openFile:
            if let bookmark = command.fileBookmark {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                    NSWorkspace.shared.open(url)
                    return .handled
                }
            }
            if let path = command.filePath {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                if FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.open(url)
                    return .handled
                }
            }
            return .failed("I could not open that file")
        }
    }

    private static func argument(_ normalized: String, prefix: String) -> String {
        if normalized.hasPrefix(prefix) {
            return String(normalized.dropFirst(prefix.count))
        }
        return normalized
    }

    private static func transform(_ kind: SelectionTransform.Kind) -> RouteResult {
        do {
            try SelectionTransform.apply(kind)
            return .handled
        } catch {
            return .failed("Nothing selected")
        }
    }
}
