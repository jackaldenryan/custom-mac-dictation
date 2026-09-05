import AppKit
import ServiceManagement
import SwiftUI

@MainActor
public final class OnboardingController {
    private var window: NSWindow?

    public func show(
        session: ListeningSession,
        store: SettingsStore,
        onlyInputSource: Bool = false,
        onFinished: @escaping () -> Void
    ) {
        if let window, !onlyInputSource {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        window?.close()
        window = nil
        let root = OnboardingView(session: session, store: store, onlyInputSource: onlyInputSource) { [weak self] in
            self?.window?.close()
            self?.window = nil
            onFinished()
        }
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = onlyInputSource ? "Input source" : "Set up Custom Dictation"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 460))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome
        case microphone
        case speech
        case accessibility
        case inputSource
        case assets
        case micPicker
        case done
    }

    let session: ListeningSession
    let store: SettingsStore
    var onlyInputSource = false
    let onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var status = ""
    @State private var assetProgress: Double = 0
    @State private var mics: [MicrophoneDevice] = []
    @State private var selectedUID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(bodyText)
                .fixedSize(horizontal: false, vertical: true)
            if !status.isEmpty {
                Text(status)
                    .foregroundStyle(.secondary)
            }
            if step == .assets, assetProgress > 0, assetProgress < 1 {
                ProgressView(value: assetProgress)
            }
            if step == .micPicker {
                Picker("Microphone", selection: $selectedUID) {
                    Text("System default").tag(Optional<String>.none)
                    ForEach(mics) { mic in
                        Text(mic.name).tag(Optional(mic.uid))
                    }
                }
            }
            Spacer()
            HStack {
                Spacer()
                if step == .inputSource {
                    Button("Skip") {
                        finishInputSource()
                    }
                }
                Button(buttonTitle, action: advance)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 460)
        .buttonStyle(PressableButtonStyle())
        .onAppear {
            mics = AudioCapture.listMicrophones()
            selectedUID = store.settings.microphoneUID
            if onlyInputSource {
                step = .inputSource
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard step == .inputSource else { return }
            if InputSourceSetup.ensure() {
                status = "Input source is selected."
            }
        }
    }

    private var title: String {
        switch step {
        case .welcome: return "Custom Dictation"
        case .microphone: return "Microphone access"
        case .speech: return "On-device speech recognition"
        case .accessibility: return "Accessibility access"
        case .inputSource: return "Keyboard input source"
        case .assets: return "Download speech models"
        case .micPicker: return "Choose your microphone"
        case .done: return "Ready"
        }
    }

    private var bodyText: String {
        switch step {
        case .welcome:
            return "This app types what you say into the focused app and runs voice commands. It uses Apple’s on-device dictation engine. Audio stays on this Mac."
        case .microphone:
            return "It needs the microphone so it can listen. Nothing is sent to a network except Apple’s one-time model download."
        case .speech:
            return "macOS may ask for Speech Recognition. Recognition runs on this Mac."
        case .accessibility:
            return "Accessibility is required so \(AppRuntime.displayName) can type and press keys in other apps. After a local rebuild, macOS treats it as a new app and this switch is off again."
        case .inputSource:
            return "macOS 26 no longer lists classic Input Method apps in Keyboard settings. Third-party keyboards there are Apple’s text-input extensions, which we cannot register yet. Leave IMK off and use Accessibility typing, or turn IMK off if this screen appeared."
        case .assets:
            return "The first launch downloads Apple’s on-device speech models if they are not already installed."
        case .micPicker:
            return "Pick the USB headset you actually use. You can change this later."
        case .done:
            return "Listening will start after you finish. Use this window or the Dock icon to turn it off. After the Mac sleeps, turn it back on from the window or Dock."
        }
    }

    private var buttonTitle: String {
        switch step {
        case .welcome: return "Continue"
        case .microphone: return "Allow microphone"
        case .speech: return "Allow speech recognition"
        case .accessibility: return "Open Accessibility settings"
        case .inputSource: return InputSourceSetup.status().isReady ? "Continue" : "Open Keyboard settings"
        case .assets: return "Download models"
        case .micPicker: return "Save microphone"
        case .done: return "Start listening"
        }
    }

    private func advance() {
        Task { await runStep() }
    }

    private func runStep() async {
        status = ""
        switch step {
        case .welcome:
            step = .microphone
        case .microphone:
            let granted = await Permissions.microphoneGranted()
            if granted {
                step = .speech
            } else {
                status = "Microphone was denied. Enable it in System Settings, then try again."
                Permissions.openMicrophoneSettings()
            }
        case .speech:
            _ = await Permissions.speechGranted()
            step = .accessibility
        case .accessibility:
            if Permissions.accessibilityGranted(prompt: true) {
                step = nextAfterAccessibility()
            } else {
                Permissions.openAccessibilitySettings()
                status = "Turn on \(AppRuntime.displayName) in Accessibility, then click again."
                if Permissions.accessibilityGranted(prompt: false) {
                    step = nextAfterAccessibility()
                }
            }
        case .inputSource:
            if InputSourceSetup.ensure() {
                finishInputSource()
            } else {
                InputSourceSetup.openSettings()
                status = "Add \(AppRuntime.displayName) under Input Sources, select it, then click again."
                if InputSourceSetup.ensure() {
                    finishInputSource()
                }
            }
        case .assets:
            status = "Downloading…"
            do {
                try await session.ensureAssets()
                step = .micPicker
            } catch {
                status = error.localizedDescription
            }
        case .micPicker:
            _ = store.update { $0.microphoneUID = selectedUID }
            step = .done
        case .done:
            _ = store.update {
                $0.hasCompletedOnboarding = true
                $0.launchAtLogin = AppRuntime.isLocalTest ? false : true
            }
            if !AppRuntime.isLocalTest {
                try? SMAppService.mainApp.register()
            }
            onFinished()
        }
    }

    private func nextAfterAccessibility() -> Step {
        store.settings.useInputMethod ? .inputSource : .assets
    }

    private func finishInputSource() {
        if onlyInputSource {
            onFinished()
        } else {
            step = .assets
        }
    }
}
