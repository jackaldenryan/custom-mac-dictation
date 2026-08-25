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

        if normalized == "start listening mac" {
            LivePhrase.discard()
            if state == .suspended { onStartListening() }
            return .handled
        }
        if state == .suspended {
            return .ignored
        }
        if normalized == "stop listening mac" {
            LivePhrase.keepAndUnhighlight()
            onStopListening()
            return .handled
        }
        if state != .listening {
            return .ignored
        }

        if let imported = matchImported(normalized: normalized, settings: settings) {
            LivePhrase.discard()
            return runImported(imported)
        }
        if let key = KeyPressGrammar.parse(normalized) {
            LivePhrase.discard()
            Typist.press(keyCode: key.keyCode, flags: key.flags, character: key.character)
            DictationSpacing.noteKeyPress(keyCode: key.keyCode)
            return .handled
        }
        if normalized.hasPrefix("open ") {
            LivePhrase.discard()
            let name = String(normalized.dropFirst(5))
            do {
                try AppController.open(spokenName: name)
                return .handled
            } catch AppControlError.notFound {
                return .failed("I could not find \(name)")
            } catch {
                return .failed("I could not open \(name)")
            }
        }
        if normalized.hasPrefix("quit ") {
            LivePhrase.discard()
            let name = String(normalized.dropFirst(5))
            do {
                try AppController.quit(spokenName: name)
                return .handled
            } catch AppControlError.notFound {
                return .failed("I could not find \(name)")
            } catch {
                return .failed("I could not quit \(name)")
            }
        }
        if normalized == "capitalize that" {
            LivePhrase.discard()
            return transform(.capitalize)
        }
        if normalized == "uppercase that" {
            LivePhrase.discard()
            return transform(.uppercase)
        }
        if normalized == "lowercase that" {
            LivePhrase.discard()
            return transform(.lowercase)
        }

        guard !trimmed.isEmpty else { return .ignored }
        LivePhrase.commit(DictationSpacing.textToType(trimmed))
        return .typed
    }

    public static func shouldHoldLive(transcript: String, state: ListeningState, settings: AppSettings) -> Bool {
        if state != .listening { return true }
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = TranscriptNormalizer.normalize(transcript)
        if normalized.isEmpty { return trimmed.isEmpty }
        if normalized.hasPrefix("start listening") || normalized.hasPrefix("stop listening") { return true }
        if normalized == "press" || normalized.hasPrefix("press ") { return true }
        if normalized == "open" || normalized.hasPrefix("open ") { return true }
        if normalized == "quit" || normalized.hasPrefix("quit ") { return true }
        if normalized.hasPrefix("capitalize") || normalized.hasPrefix("uppercase") || normalized.hasPrefix("lowercase") {
            return true
        }
        if matchImported(normalized: normalized, settings: settings) != nil {
            return true
        }
        return settings.commands.contains { command in
            guard command.enabled else { return false }
            return command.phrases.contains { phrase in
                let name = TranscriptNormalizer.normalize(phrase)
                return name.hasPrefix(normalized) && normalized.count >= 3
            }
        }
    }

    private static func transform(_ kind: SelectionTransform.Kind) -> RouteResult {
        do {
            try SelectionTransform.apply(kind)
            return .handled
        } catch {
            return .failed("Nothing selected")
        }
    }

    private static func matchImported(normalized: String, settings: AppSettings) -> ImportedCommand? {
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let matches = settings.commands.filter { command in
            guard command.enabled else { return false }
            if let scope = command.scopeBundleID, scope != frontID { return false }
            return command.phrases.contains { TranscriptNormalizer.normalize($0) == normalized }
        }
        return matches.max { $0.phrases.joined().count < $1.phrases.joined().count }
    }

    private static func runImported(_ command: ImportedCommand) -> RouteResult {
        switch command.kind {
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
}
