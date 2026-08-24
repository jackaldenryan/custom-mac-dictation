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
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 640, height: 520))
        window.minSize = NSSize(width: 560, height: 420)
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
    @ObservedObject var session: ListeningSession
    let store: SettingsStore
    @ObservedObject var updater: UpdateController
    @State private var settings: AppSettings = .default
    @State private var mics: [MicrophoneDevice] = []
    @State private var logText = ""

    var body: some View {
        TabView {
            listeningTab
                .tabItem { Text("Listening") }
            updatesTab
                .tabItem { Text("Updates") }
            vocabularyTab
                .tabItem { Text("Vocabulary") }
            punctuationTab
                .tabItem { Text("Punctuation") }
            diagnosticsTab
                .tabItem { Text("Diagnostics") }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 400)
        .onAppear {
            settings = store.settings
            mics = AudioCapture.listMicrophones()
            logText = DiagnosticLog.tail()
        }
    }

    private var listeningTab: some View {
        Form {
            Section("Status") {
                Text("State: \(session.state.rawValue)")
                if !session.lastError.isEmpty {
                    Text(session.lastError)
                        .foregroundStyle(.red)
                }
            }
            Section("Microphone") {
                Picker("Input", selection: microphoneBinding) {
                    Text("System default").tag(Optional<String>.none)
                    ForEach(mics) { mic in
                        Text(mic.name).tag(Optional(mic.uid))
                    }
                }
            }
            Section("Startup") {
                Toggle("Open at login", isOn: launchBinding)
            }
        }
        .formStyle(.grouped)
    }

    private var updatesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Updates")
                .font(.title3.weight(.semibold))
            Text("Current version \(AppVersion.current)")
            Text(updater.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var vocabularyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vocabulary and commands")
                .font(.title3.weight(.semibold))
            Text("\(settings.vocabulary.count) vocabulary entries, \(settings.commands.count) custom commands.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Import from Voice Control") { importVoiceControl() }
                Button("Export…") { exportJSON() }
                Button("Import file…") { importJSON() }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var punctuationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Punctuation defaults")
                    .font(.title3.weight(.semibold))
                Text("Choose whether a spoken name types the character or the word.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(PunctuationPolicy.table, id: \.names[0]) { entry in
                    Picker(entry.names[0], selection: punctuationBinding(entry.names[0])) {
                        Text("Character \(entry.character)").tag(PunctuationMode.character)
                        Text("Literal word").tag(PunctuationMode.word)
                        Text("Off").tag(PunctuationMode.off)
                    }
                }
            }
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var diagnosticsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics")
                .font(.title3.weight(.semibold))
            Text("Last heard: \(session.lastFinal.isEmpty ? "—" : session.lastFinal)")
            Text("Last route: \(session.lastRoute.isEmpty ? "—" : session.lastRoute)")
            ScrollView {
                Text(logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .border(Color.secondary.opacity(0.3))
            HStack {
                Button("Refresh log") { logText = DiagnosticLog.tail() }
                Button("Copy log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(DiagnosticLog.tail(), forType: .string)
                }
                Button("Show log file") { DiagnosticLog.revealInFinder() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
