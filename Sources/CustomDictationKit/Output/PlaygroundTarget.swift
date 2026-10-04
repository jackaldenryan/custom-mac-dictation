import Combine
import Foundation

public final class PlaygroundTarget: @unchecked Sendable, ObservableObject {
    public static let shared = PlaygroundTarget()

    @Published public var box: FieldBox = .notes {
        didSet { resetField() }
    }
    @Published public var text = ""
    @Published public var logText = ""
    @Published public var isActive = false

    public var field = SimulatedField(box: .notes)
    private var lines: [String] = []
    private let lock = NSLock()

    public func activate() {
        guard !isActive else { return }
        isActive = true
        event("capture on")
    }

    public func deactivate() {
        guard isActive else { return }
        isActive = false
        collapseLive()
        event("capture off")
    }

    public func resetField() {
        field = SimulatedField(box: box, text: "")
        text = ""
        event("reset box=\(box.rawValue) imk=\(LivePhrase.usesInputMethod())")
    }

    public func clearLog() {
        lock.lock()
        lines = []
        lock.unlock()
        logText = ""
        event("log cleared box=\(box.rawValue)")
    }

    public func refreshLog() {
        lock.lock()
        let copy = lines
        lock.unlock()
        logText = copy.joined(separator: "\n")
    }

    public func copyLog() -> String {
        lock.lock()
        let copy = lines
        lock.unlock()
        return copy.joined(separator: "\n")
    }

    public func event(_ message: String) {
        let stamp = ISO8601DateFormatter.string(
            from: Date(),
            timeZone: .current,
            formatOptions: [.withInternetDateTime, .withFractionalSeconds]
        )
        let line = "[\(stamp)] box=\(box.rawValue) \(message)"
        lock.lock()
        lines.append(line)
        let joined = lines.joined(separator: "\n")
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.logText = joined
        }
        DiagnosticLog.line("PLAYGROUND \(message)")
    }

    public func apply(shaped: String, keepSelected: Bool, isPartial: Bool) -> LiveInsertPath {
        let settings = SettingsStore.shared.settings
        let before = field.text
        let sel = "\(field.loc)+\(field.len)"
        field.apply(shaped: shaped, keepSelected: keepSelected, useInputMethod: LivePhrase.usesInputMethod())
        if !isPartial {
            field.finishIfNeeded()
        }
        text = field.text
        event(
             "write partial=\(isPartial ? 1 : 0) path=\(field.lastPath.rawValue) shaped=\(String(reflecting: shaped)) sel=\(sel) before=\(String(reflecting: before)) after=\(String(reflecting: field.text)) caret=\(field.loc)+\(field.len) lastTypedAge=\(String(format: "%.3f", Date().timeIntervalSince(LivePhrase.lastTypedAt))) finalize=\(settings.finalizeDelaySeconds) finalizeOff=\(settings.disableFinalizeDelay ? 1 : 0) punctDelay=\(settings.effectiveLonePunctuationDelay) punctOff=\(settings.disableLonePunctuationDelay ? 1 : 0) postOnlyFinal=\(settings.postProcessOnlyOnFinal ? 1 : 0) imk=\(LivePhrase.usesInputMethod())"
        )
        return field.lastPath
    }

    public func collapseLive() {
        field.finishIfNeeded()
        field.len = 0
        field.displayed = ""
        field.liveVisible = false
        text = field.text
        objectWillChange.send()
        event("unhighlight caret=\(field.loc)+\(field.len)")
    }

    public func syncSelection(loc: Int, len: Int) {
        field.loc = loc
        field.len = len
        field.displayed = ""
        event("selection loc=\(loc) len=\(len) text=\(String(reflecting: field.text))")
    }
}
