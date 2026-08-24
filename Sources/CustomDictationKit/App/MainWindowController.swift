import AppKit
import ApplicationServices
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
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 480, height: 420))
        window.minSize = NSSize(width: 420, height: 360)
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
    @State private var scratch = ""
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(statusTitle)
                .font(.title2.weight(.semibold))
            Text(statusDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !session.lastError.isEmpty {
                Text(session.lastError)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !accessibilityTrusted {
                Text("Accessibility is off, so nothing can be typed into other apps. Enable Custom Dictation in System Settings → Privacy & Security → Accessibility.")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            GroupBox("Try it here") {
                TextField("Click this box, then speak", text: $scratch, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }
            if !session.lastPartial.isEmpty {
                Text("Hearing: \(session.lastPartial)")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if !session.lastFinal.isEmpty {
                Text("Heard: \(session.lastFinal)")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 340)
        .onAppear { accessibilityTrusted = AXIsProcessTrusted() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibilityTrusted = AXIsProcessTrusted()
        }
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
            return "The microphone is off. Start listening, click the box below or another app, then speak."
        case .suspended:
            return "Say “start listening Mac” or click Resume."
        case .listening:
            return "Click the box below or another app, then speak. Say “stop listening Mac” to pause."
        }
    }
}
