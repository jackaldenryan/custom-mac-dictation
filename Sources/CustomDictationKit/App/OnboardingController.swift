import AppKit
import ServiceManagement
import SwiftUI

@MainActor
public final class OnboardingController {
    private var window: NSWindow?

    public func show(session: ListeningSession, store: SettingsStore, onFinished: @escaping () -> Void) {
        let root = OnboardingView(session: session, store: store) { [weak self] in
            self?.window?.close()
            self?.window = nil
            onFinished()
        }
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Set up Custom Dictation"
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
        case assets
        case importVoiceControl
        case micPicker
        case done
    }

    let session: ListeningSession
    let store: SettingsStore
    let onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var status = ""
    @State private var assetProgress: Double = 0
    @State private var mics: [MicrophoneDevice] = []
    @State private var selectedUID: String?
    @State private var importSummary = ""

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
            if step == .importVoiceControl, !importSummary.isEmpty {
                Text(importSummary)
            }
            Spacer()
            HStack {
                Spacer()
                Button(buttonTitle, action: advance)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 460)
        .onAppear {
            mics = AudioCapture.listMicrophones()
            selectedUID = store.settings.microphoneUID
        }
    }

    private var title: String {
        switch step {
        case .welcome: return "Custom Dictation"
        case .microphone: return "Microphone access"
        case .speech: return "On-device speech recognition"
        case .accessibility: return "Accessibility access"
        case .assets: return "Download speech models"
        case .importVoiceControl: return "Import Voice Control"
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
            return "Accessibility is required so the app can type and press keys in other apps. It does not read other apps’ interface trees."
        case .assets:
            return "The first launch downloads Apple’s on-device speech models if they are not already installed."
        case .importVoiceControl:
            return "Import your existing Voice Control vocabulary and custom commands in one step. You can skip this and import later from Settings."
        case .micPicker:
            return "Pick the USB headset you actually use. You can change this later."
        case .done:
            return "Listening will start after you finish. Use the menu bar icon to turn it off. After the Mac sleeps, turn it back on from that icon."
        }
    }

    private var buttonTitle: String {
        switch step {
        case .welcome: return "Continue"
        case .microphone: return "Allow microphone"
        case .speech: return "Allow speech recognition"
        case .accessibility: return "Open Accessibility settings"
        case .assets: return "Download models"
        case .importVoiceControl: return "Import now"
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
                step = .assets
            } else {
                Permissions.openAccessibilitySettings()
                status = "Turn on Custom Dictation in Accessibility, then click again."
                if Permissions.accessibilityGranted(prompt: false) {
                    step = .assets
                }
            }
        case .assets:
            status = "Downloading…"
            do {
                try await session.ensureAssets()
                step = .importVoiceControl
            } catch {
                status = error.localizedDescription
            }
        case .importVoiceControl:
            do {
                let result = try VoiceControlImporter.importFromThisMac()
                _ = store.update {
                    $0.vocabulary = result.vocabulary
                    $0.commands = result.commands
                }
                importSummary = "Imported \(result.vocabulary.count) vocabulary entries and \(result.commands.count) commands."
            } catch {
                importSummary = "Import failed: \(error.localizedDescription). You can try again later."
            }
            step = .micPicker
        case .micPicker:
            _ = store.update { $0.microphoneUID = selectedUID }
            step = .done
        case .done:
            _ = store.update {
                $0.hasCompletedOnboarding = true
                $0.launchAtLogin = true
            }
            try? SMAppService.mainApp.register()
            onFinished()
        }
    }
}
