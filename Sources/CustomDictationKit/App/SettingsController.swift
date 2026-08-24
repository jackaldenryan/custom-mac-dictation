import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class SettingsController {
    private var window: NSWindow?

    public func show(session: ListeningSession, store: SettingsStore, updater: UpdateController) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = SettingsView(session: session, store: store, updater: updater)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Custom Dictation Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 620, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

public final class UpdateController: ObservableObject {
    @Published public var message = "Current version \(AppVersion.current)."
    @Published public var checking = false
    @Published public var pending: AvailableUpdate?
    @Published public var installing = false

    @MainActor
    public func check(interactive: Bool) async {
        checking = true
        if interactive {
            message = "Checking for updates…"
        }
        let result = await UpdateChecker.check()
        checking = false
        switch result {
        case .upToDate(let version):
            pending = nil
            if interactive {
                message = "Version \(version) is up to date."
            }
        case .available(let update):
            pending = update
            message = "Version \(update.version) is available."
        case .failed(let error):
            if interactive {
                message = error
            }
        }
    }

    @MainActor
    public func installPending() async {
        guard let pending else { return }
        installing = true
        do {
            try await UpdateChecker.install(pending)
        } catch {
            message = error.localizedDescription
            installing = false
        }
    }
}

private struct SettingsView: View {
    let session: ListeningSession
    let store: SettingsStore
    @ObservedObject var updater: UpdateController
    @State private var settings: AppSettings = .default
    @State private var neverQuitDraft = ""
    @State private var mics: [MicrophoneDevice] = []

    var body: some View {
        Form {
            Section("Listening") {
                Text("State: \(session.state.rawValue)")
                Picker("Microphone", selection: microphoneBinding) {
                    Text("System default").tag(Optional<String>.none)
                    ForEach(mics) { mic in
                        Text(mic.name).tag(Optional(mic.uid))
                    }
                }
                Toggle("Open at login", isOn: launchBinding)
            }
            Section("Updates") {
                Text("Current version \(AppVersion.current)")
                Text(updater.message)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(updater.checking ? "Checking…" : "Check for updates") {
                        Task { await updater.check(interactive: true) }
                    }
                    .disabled(updater.checking || updater.installing)
                    if updater.pending != nil {
                        Button(updater.installing ? "Updating…" : "Install update") {
                            Task { await updater.installPending() }
                        }
                        .disabled(updater.installing)
                        Button("Later") {
                            updater.pending = nil
                        }
                        .disabled(updater.installing)
                    }
                }
            }
            Section("Never quit by voice") {
                ForEach(settings.neverQuitNames, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button("Remove") {
                            settings.neverQuitNames.removeAll { $0 == name }
                            persist()
                        }
                    }
                }
                HStack {
                    TextField("App name", text: $neverQuitDraft)
                    Button("Add") {
                        let name = neverQuitDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        if !settings.neverQuitNames.contains(name) {
                            settings.neverQuitNames.append(name)
                            persist()
                        }
                        neverQuitDraft = ""
                    }
                }
            }
            Section("Vocabulary and commands") {
                Text("\(settings.vocabulary.count) vocabulary entries, \(settings.commands.count) custom commands.")
                HStack {
                    Button("Import from Voice Control") { importVoiceControl() }
                    Button("Export…") { exportJSON() }
                    Button("Import file…") { importJSON() }
                }
            }
            Section("Punctuation defaults") {
                ForEach(PunctuationPolicy.table, id: \.names[0]) { entry in
                    Picker(entry.names[0], selection: punctuationBinding(entry.names[0])) {
                        Text("Character \(entry.character)").tag(PunctuationMode.character)
                        Text("Literal word").tag(PunctuationMode.word)
                        Text("Off").tag(PunctuationMode.off)
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 600, minHeight: 520)
        .onAppear {
            settings = store.settings
            mics = AudioCapture.listMicrophones()
        }
    }

    private var microphoneBinding: Binding<String?> {
        Binding(
            get: { settings.microphoneUID },
            set: { settings.microphoneUID = $0; persist() }
        )
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { newValue in
                settings.launchAtLogin = newValue
                persist()
                if newValue {
                    try? SMAppService.mainApp.register()
                } else {
                    try? SMAppService.mainApp.unregister()
                }
            }
        )
    }

    private func punctuationBinding(_ word: String) -> Binding<PunctuationMode> {
        Binding(
            get: { settings.punctuationModes[word] ?? .character },
            set: { settings.punctuationModes[word] = $0; persist() }
        )
    }

    private func persist() {
        _ = store.update { $0 = settings }
        settings = store.settings
    }

    private func importVoiceControl() {
        do {
            let result = try VoiceControlImporter.importFromThisMac()
            settings.vocabulary = result.vocabulary
            settings.commands = result.commands
            persist()
            updater.message = "Imported \(result.vocabulary.count) words and \(result.commands.count) commands."
        } catch {
            updater.message = error.localizedDescription
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "custom-dictation-vocabulary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try VocabularyStore.exportJSON(settings: settings, to: url)
        } catch {
            updater.message = error.localizedDescription
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        do {
            let file = try VocabularyStore.importJSON(from: url)
            settings.vocabulary = file.vocabulary
            settings.commands = file.commands
            persist()
        } catch {
            updater.message = error.localizedDescription
        }
    }
}
