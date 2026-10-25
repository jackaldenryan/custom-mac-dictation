import AppKit
import Foundation

/// Identity of the focused text destination, not just its app or AX role.
/// AX elements compare by CFEqual in production; tests supply stable IDs.
public struct DictationTarget: Equatable {
    public let processID: Int32
    public let elementID: AnyHashable

    public init(processID: Int32, elementID: AnyHashable) {
        self.processID = processID
        self.elementID = elementID
    }
}

/// The boundary between phrase handling and macOS. Tests exercise the real
/// LivePhrase state machine with a recording output, without posting keys.
public protocol DictationOutput: AnyObject {
    var frontAppID: String { get }
    func target() -> DictationTarget?
    func snapshot() -> CaretSnapshot?
    func replaceLive(_ text: String, select: Bool, target: DictationTarget) -> Bool
    func typeText(_ text: String, target: DictationTarget) -> Bool
    func deleteBackward(_ count: Int, target: DictationTarget) -> Bool
    func finishLive(target: DictationTarget)
    func clearLive()
}

final class SystemDictationOutput: DictationOutput {
    var frontAppID: String { NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "" }
    func target() -> DictationTarget? { FieldEditor.dictationTarget() }
    func snapshot() -> CaretSnapshot? { InsertionContext.snapshot() }
    func replaceLive(_ text: String, select: Bool, target: DictationTarget) -> Bool {
        guard self.target() == target else { return false }
        return FieldEditor.replaceLive(with: text, select: select, target: target)
    }
    func typeText(_ text: String, target: DictationTarget) -> Bool {
        Typist.typeText(text, target: target)
    }
    func deleteBackward(_ count: Int, target: DictationTarget) -> Bool {
        Typist.deleteDictationBackward(times: count, target: target)
    }
    func finishLive(target: DictationTarget) {
        guard self.target() == target else { FieldEditor.clearLive(); return }
        FieldEditor.finishLive()
    }
    func clearLive() { FieldEditor.clearLive() }
}

public enum DictationKeyEvent: Equatable {
    case text([UInt16])
    case backspace
}

/// Shared by the real Typist and tests. Validate before every Unicode chunk
/// and every correction key, not just before starting a long emission.
public struct DictationKeyWriter {
    private let currentTarget: () -> DictationTarget?
    private let post: (DictationKeyEvent, Int32) -> Void

    public init(currentTarget: @escaping () -> DictationTarget?,
                post: @escaping (DictationKeyEvent, Int32) -> Void) {
        self.currentTarget = currentTarget
        self.post = post
    }

    public func write(_ text: String, target: DictationTarget) -> Bool {
        // Chunk at Character boundaries so a surrogate pair / emoji is
        // never split between keyboard events.
        var chunk: [UInt16] = []
        for character in text {
            let units = Array(String(character).utf16)
            if !chunk.isEmpty, chunk.count + units.count > 20 {
                guard emit(.text(chunk), target: target) else { return false }
                chunk.removeAll(keepingCapacity: true)
            }
            chunk.append(contentsOf: units)
        }
        if !chunk.isEmpty, !emit(.text(chunk), target: target) { return false }
        return currentTarget() == target
    }

    public func deleteBackward(_ count: Int, target: DictationTarget) -> Bool {
        for _ in 0..<max(0, count) {
            guard emit(.backspace, target: target) else { return false }
        }
        return currentTarget() == target
    }

    private func emit(_ event: DictationKeyEvent, target: DictationTarget) -> Bool {
        guard currentTarget() == target else { return false }
        post(event, target.processID)
        return true
    }
}
