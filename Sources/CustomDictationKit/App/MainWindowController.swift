import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class MainWindowController {
    private var window: NSWindow?

    public func show(session: ListeningSession, store: SettingsStore, updater: UpdateController) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let root = AppRootView(session: session, store: store, updater: updater)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Custom Dictation"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.setContentSize(NSSize(width: 980, height: 680))
        window.minSize = NSSize(width: 720, height: 480)
        window.setFrameAutosaveName("CustomDictation.Main")
        window.isRestorable = true
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }
}

private struct AppRootView: View {
    @ObservedObject var session: ListeningSession
    let store: SettingsStore
    @ObservedObject var updater: UpdateController
    @State private var settings: AppSettings = .default
    @State private var mics: [MicrophoneDevice] = []
    @State private var logText = ""
    @State private var scratch = ""
    @State private var accessibilityTrusted = AXIsProcessTrusted()

    var body: some View {
        TabView {
            listenTab
                .tabItem { Label("Listen", systemImage: "mic.fill") }
            vocabularyTab
                .tabItem { Label("Vocabulary", systemImage: "text.book.closed") }
            punctuationTab
                .tabItem { Label("Punctuation", systemImage: "textformat") }
            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            diagnosticsTab
                .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            settings = store.settings
            mics = AudioCapture.listMicrophones()
            logText = DiagnosticLog.tail()
            accessibilityTrusted = AXIsProcessTrusted()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibilityTrusted = AXIsProcessTrusted()
        }
    }

    private var listenTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(statusTitle)
                .font(.largeTitle.weight(.semibold))
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
                        Button("Pause") { session.suspend() }
                    } else if session.state == .suspended {
                        Button("Resume") { session.resumeFromSuspend() }
                    }
                }
            }
            GroupBox("Try it here") {
                TextEditor(text: $scratch)
                    .font(.body)
                    .frame(minHeight: 160)
            }
            if !session.lastPartial.isEmpty {
                Text("Hearing: \(session.lastPartial)")
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else if !session.lastFinal.isEmpty {
                Text("Heard: \(session.lastFinal)")
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Form {
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var updatesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Updates")
                .font(.title2.weight(.semibold))
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
                .font(.title2.weight(.semibold))
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
                    .font(.title2.weight(.semibold))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var diagnosticsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics")
                .font(.title2.weight(.semibold))
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
