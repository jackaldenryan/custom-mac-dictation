import AppKit
import SwiftUI

/// Small pop-up in the bottom-right corner offering a new version. It never
/// takes keyboard focus, so it can't interrupt dictation into another app.
@MainActor
final class UpdatePromptController {
    private var panel: NSPanel?

    var isShowing: Bool { panel?.isVisible == true }

    func show(version: String, onUpdate: @escaping () -> Void, onNotNow: @escaping () -> Void) {
        close()
        let view = UpdatePromptView(
            version: version,
            onUpdate: { [weak self] in
                self?.close()
                onUpdate()
            },
            onNotNow: { [weak self] in
                self?.close()
                onNotNow()
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let margin: CGFloat = 16
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - panel.frame.width - margin,
                y: visible.minY + margin
            ))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct UpdatePromptView: View {
    let version: String
    let onUpdate: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom Dictation \(version) is available")
                .font(.headline)
            Text("Update now? The app restarts on the new version.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Not now", action: onNotNow)
                    .buttonStyle(PressableButtonStyle())
                Button("Update", action: onUpdate)
                    .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
