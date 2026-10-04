import AppKit
import SwiftUI

public struct PlaygroundView: View {
    @ObservedObject var session: ListeningSession
    @ObservedObject var target: PlaygroundTarget

    public init(session: ListeningSession, target: PlaygroundTarget = .shared) {
        self.session = session
        self.target = target
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playground")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Pick a box type, click the field, then speak. Output stays in this field and the log. Copy the log after a failure.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Picker("Box", selection: $target.box) {
                    ForEach(FieldBox.allCases) { box in
                        Text(box.title).tag(box)
                    }
                }
                .frame(maxWidth: 280)
                Text(target.isActive ? "Capturing" : "Click the field to capture")
                    .foregroundStyle(target.isActive ? .green : .secondary)
                Text(LivePhrase.usesInputMethod() ? "IMK on" : "AX/HID")
                    .foregroundStyle(.secondary)
                if target.isActive {
                    FlashButton(title: "Stop capturing", doneTitle: "Stopped") {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                        target.deactivate()
                    }
                }
                Spacer()
                FlashButton(title: "Clear field", doneTitle: "Cleared") { target.resetField() }
                FlashButton(title: "Refresh log", doneTitle: "Refreshed") { target.refreshLog() }
                FlashButton(title: "Copy log", doneTitle: "Copied") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(target.copyLog(), forType: .string)
                }
                FlashButton(title: "Clear log", doneTitle: "Cleared") { target.clearLog() }
            }
            PlaygroundFieldView(target: target)
                .frame(minHeight: 140)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            Text(session.lastPartial.isEmpty ? (session.lastFinal.isEmpty ? " " : "Heard: \(session.lastFinal)") : "Hearing: \(session.lastPartial)")
                .foregroundStyle(.secondary)
                .lineLimit(2)
            ScrollView {
                Text(target.logText.isEmpty ? "Log is empty. Speak into the field." : target.logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            target.deactivate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            target.deactivate()
        }
        .onDisappear {
            target.deactivate()
        }
    }
}

private struct PlaygroundFieldView: NSViewRepresentable {
    @ObservedObject var target: PlaygroundTarget

    func makeCoordinator() -> Coordinator {
        Coordinator(target: target)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let view = PlaygroundTextView()
        view.focusHandler = { focused in
            if focused {
                context.coordinator.target.activate()
            } else {
                context.coordinator.target.deactivate()
            }
        }
        view.delegate = context.coordinator
        view.isRichText = false
        view.font = .systemFont(ofSize: 15)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.textContainerInset = NSSize(width: 8, height: 8)
        context.coordinator.textView = view
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let view = nsView.documentView as? NSTextView else { return }
        let want = NSRange(location: max(0, target.field.loc), length: max(0, target.field.len))
        context.coordinator.ignoreSelection = true
        if view.string != target.text {
            view.string = target.text
        }
        let ns = view.string as NSString
        let loc = min(want.location, ns.length)
        let len = min(want.length, max(0, ns.length - loc))
        view.setSelectedRange(NSRange(location: loc, length: len))
        context.coordinator.ignoreSelection = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let target: PlaygroundTarget
        weak var textView: NSTextView?
        var ignoreSelection = false

        init(target: PlaygroundTarget) {
            self.target = target
        }

        func textDidBeginEditing(_ notification: Notification) {
            target.activate()
        }

        func textDidEndEditing(_ notification: Notification) {
            target.deactivate()
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            target.text = view.string
            target.field.text = view.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !ignoreSelection, let view = notification.object as? NSTextView else { return }
            let range = view.selectedRange()
            target.syncSelection(loc: range.location, len: range.length)
        }
    }
}

private final class PlaygroundTextView: NSTextView {
    var focusHandler: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { focusHandler?(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { focusHandler?(false) }
        return ok
    }
}
