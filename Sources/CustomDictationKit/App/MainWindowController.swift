import AppKit
import SwiftUI

@MainActor
public final class MainWindowController {
    private var window: NSWindow?

    public func show(session: ListeningSession, onOpenSettings: @escaping () -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = MainView(session: session, onOpenSettings: onOpenSettings)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Custom Dictation"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 420, height: 240))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct MainView: View {
    @ObservedObject var session: ListeningSession
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(statusTitle)
                .font(.title2.weight(.semibold))
            Text(statusDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if session.state == .off {
                    Button("Start Listening") {
                        Task { await session.startListening() }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Stop Listening") {
                        Task { await session.stopCompletely() }
                    }
                    if session.state == .listening {
                        Button("Pause") {
                            session.suspend()
                        }
                    } else if session.state == .suspended {
                        Button("Resume") {
                            session.resumeFromSuspend()
                        }
                    }
                }
                Button("Settings…", action: onOpenSettings)
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 420, height: 240)
    }

    private var statusTitle: String {
        switch session.state {
        case .off: return "Listening is off"
        case .suspended: return "Listening is paused"
        case .listening: return "Listening"
        }
    }

    private var statusDetail: String {
        switch session.state {
        case .off:
            return "The microphone is off. Start listening to dictate into the focused app."
        case .suspended:
            return "Say “start listening Mac” or click Resume."
        case .listening:
            return "Speak to type. Say “stop listening Mac” to pause."
        }
    }
}
