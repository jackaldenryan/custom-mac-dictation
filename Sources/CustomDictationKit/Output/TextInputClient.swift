import Foundation

public protocol TextInputClient: AnyObject {
    var isAvailable: Bool { get }
    func selectedRange() -> NSRange
    func selectedString() -> String?
    func setMarkedText(_ string: String)
    func insertText(_ string: String)
    func unmarkText()
    func caretSnapshot() -> CaretSnapshot?
}

public enum DictationTextInput {
    nonisolated(unsafe) public static var override: TextInputClient?

    public static var current: TextInputClient {
        override ?? IMKSessionClient.shared
    }
}

public final class MemoryTextInput: TextInputClient {
    public var text: String
    public var location: Int
    public var length: Int
    public var isAvailable: Bool
    private var marked: NSRange?

    public init(text: String = "", location: Int? = nil, length: Int = 0, isAvailable: Bool = true) {
        self.text = text
        self.location = location ?? (text as NSString).length
        self.length = length
        self.isAvailable = isAvailable
    }

    public func selectedRange() -> NSRange {
        NSRange(location: location, length: length)
    }

    public func selectedString() -> String? {
        guard isAvailable, length > 0 else { return nil }
        let ns = text as NSString
        let loc = min(max(0, location), ns.length)
        let len = min(length, ns.length - loc)
        guard len > 0 else { return nil }
        return ns.substring(with: NSRange(location: loc, length: len))
    }

    public func setMarkedText(_ string: String) {
        guard isAvailable else { return }
        let range = marked ?? NSRange(location: location, length: length)
        replace(range, with: string)
        let mark = NSRange(location: range.location, length: (string as NSString).length)
        marked = mark
        location = mark.location
        length = mark.length
    }

    public func insertText(_ string: String) {
        guard isAvailable else { return }
        let range = marked ?? NSRange(location: location, length: length)
        replace(range, with: string)
        marked = nil
        location = range.location + (string as NSString).length
        length = 0
    }

    public func unmarkText() {
        guard isAvailable, let mark = marked else { return }
        location = mark.location + mark.length
        length = 0
        marked = nil
    }

    public func caretSnapshot() -> CaretSnapshot? {
        guard isAvailable else { return nil }
        return InsertionContext.snapshot(in: text, utf16Location: location, utf16Length: length)
    }

    private func replace(_ range: NSRange, with string: String) {
        let ns = text as NSString
        let loc = min(max(0, range.location), ns.length)
        let len = min(max(0, range.length), ns.length - loc)
        text = ns.replacingCharacters(in: NSRange(location: loc, length: len), with: string)
    }
}
