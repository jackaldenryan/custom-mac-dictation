import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    public func show(session: ListeningSession, store: SettingsStore, updater: UpdateController) {
        NSApp.setActivationPolicy(.regular)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let root = AppRootView(session: session, store: store, updater: updater)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "Custom Dictation"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.minSize = NSSize(width: 720, height: 480)
        window.setFrameAutosaveName("CustomDictation.Main.v3")
        window.isRestorable = true
        window.isReleasedWhenClosed = false
        if !window.setFrameUsingName("CustomDictation.Main.v3") {
            window.setContentSize(NSSize(width: 980, height: 680))
            window.center()
        }
        fit(window)
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func fit(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        if frame.width > visible.width { frame.size.width = visible.width }
        if frame.height > visible.height { frame.size.height = visible.height }
        if frame.minX < visible.minX { frame.origin.x = visible.minX }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
        window.setFrame(frame, display: true)
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
    @State private var newWord = ""
    @State private var newIPA = ""
    @State private var vocabMessage = ""
    @State private var commandMessage = ""
    @State private var importingVoiceControl = false
    @State private var newPhrase = ""
    @State private var newCommandKind: CustomCommandKind = .pasteText
    @State private var newPasteText = ""
    @State private var newShortcut = ""
    @State private var newFilePath = ""
    @State private var newFileBookmark: Data?
    @State private var customFinalizeText = ""
    @State private var finalizeUsesCustom = false
    @State private var customKeyRepeatText = ""
    @State private var keyRepeatUsesCustom = false
    @State private var customLonePunctText = ""
    @State private var lonePunctUsesCustom = false
    @State private var postProcessName = PostProcessConfig.builtInDefault.name
    @State private var postProcessScript = PostProcessConfig.builtInDefault.script
    @State private var postProcessMessage = ""
    @State private var section: AppSection = .listen
    @State private var vocabSearch = ""
    @State private var commandSearch = ""
    @State private var selectedVocab = Set<String>()
    @State private var selectedCommands = Set<String>()
    @State private var showFormat = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AppSection.allCases, id: \.self) { item in
                    Button {
                        section = item
                    } label: {
                        Label(item.title, systemImage: item.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(section == item ? Color.accentColor.opacity(0.18) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: 200)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            Group {
                switch section {
                case .listen: listenTab
                case .vocabulary: vocabularyTab
                case .commands: commandsTab
                case .postProcess: postProcessTab
                case .updates: updatesTab
                case .diagnostics: diagnosticsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            settings = store.settings
            customFinalizeText = Self.finalizeFieldText(settings.finalizeDelaySeconds)
            mics = AudioCapture.listMicrophones()
            logText = DiagnosticLog.tail()
            accessibilityTrusted = AXIsProcessTrusted()
            loadPostProcessDraft()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            accessibilityTrusted = AXIsProcessTrusted()
        }
        .onReceive(NotificationCenter.default.publisher(for: ConfigFolder.didChange)) { _ in
            store.reloadFromFolder()
            settings = store.settings
        }
    }

    private var listenTab: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text(statusTitle)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
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
            HStack(spacing: 10) {
                if session.state == .listening {
                    Button("Stop Listening") {
                        Task { await session.stopCompletely() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button("Start Listening") {
                        Task { await session.startListening() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Try it here")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $scratch)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 160)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            }
            if !session.lastPartial.isEmpty {
                Text("Hearing: \(session.lastPartial)")
                    .underline()
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                Text("Still finalizing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Section("Finish a phrase after") {
                    Picker("Silence", selection: finalizeMenuBinding) {
                        ForEach(0...20, id: \.self) { tenths in
                            Text(Self.finalizeMenuLabel(tenths: tenths)).tag(FinalizeMenu.tenths(tenths))
                        }
                        Text("Custom").tag(FinalizeMenu.custom)
                    }
                    if finalizeMenu == .custom {
                        HStack {
                            TextField("Seconds", text: $customFinalizeText)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                                .onSubmit { applyCustomFinalizeDelay() }
                            Text("seconds")
                                .foregroundStyle(.secondary)
                            Button("Apply") { applyCustomFinalizeDelay() }
                        }
                    }
                    Text("How long to wait after you stop talking before the phrase is finished. Longer can keep Apple from adding a second period or question mark.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Pause between repeated keys") {
                    Picker("Delay", selection: keyRepeatMenuBinding) {
                        ForEach([0, 40, 80, 120, 160, 200, 300, 500], id: \.self) { millis in
                            Text(Self.keyRepeatMenuLabel(millis: millis)).tag(KeyRepeatMenu.millis(millis))
                        }
                        Text("Custom").tag(KeyRepeatMenu.custom)
                    }
                    if keyRepeatMenu == .custom {
                        HStack {
                            TextField("Seconds", text: $customKeyRepeatText)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                                .onSubmit { applyCustomKeyRepeatDelay() }
                            Text("seconds")
                                .foregroundStyle(.secondary)
                            Button("Apply") { applyCustomKeyRepeatDelay() }
                        }
                    }
                    Text("Used when you say “press the page down key five times”. Default is 0.08 seconds.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("Lone comma or period after") {
                    Picker("Pause", selection: lonePunctMenuBinding) {
                        ForEach([0, 5, 10, 15, 20, 30], id: \.self) { tenths in
                            Text(Self.finalizeMenuLabel(tenths: tenths)).tag(LonePunctMenu.tenths(tenths))
                        }
                        Text("Custom").tag(LonePunctMenu.custom)
                    }
                    if lonePunctMenu == .custom {
                        HStack {
                            TextField("Seconds", text: $customLonePunctText)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                                .onSubmit { applyCustomLonePunctDelay() }
                            Text("seconds")
                                .foregroundStyle(.secondary)
                            Button("Apply") { applyCustomLonePunctDelay() }
                        }
                    }
                    Text("A leftover period or question mark right after a phrase is ignored. After this pause, a lone “,” or “.” is typed. Default is 1 second.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var postProcessTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Post-process")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Runs only after a phrase is routed as typed text, not on commands. Default is the built-in rules. Duplicate it to experiment. function process(ctx) must return the string to type, or null to ignore.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Picker("Configuration", selection: postProcessIDBinding) {
                    ForEach(settings.postProcessConfigs) { config in
                        Text(config.name).tag(config.id)
                    }
                }
                Button("Duplicate") { duplicatePostProcess() }
                Button("New") { newPostProcess() }
                Button("Delete") { deletePostProcess() }
                    .disabled(settings.activePostProcessConfig.isBuiltInDefault || settings.postProcessConfigs.count < 2)
            }
            TextField("Name", text: $postProcessName)
                .textFieldStyle(.roundedBorder)
                .disabled(settings.activePostProcessConfig.isBuiltInDefault)
                .onSubmit { savePostProcessDraft() }
            TextEditor(text: $postProcessScript)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .disabled(settings.activePostProcessConfig.isBuiltInDefault)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            HStack {
                Button("Save") { savePostProcessDraft() }
                    .disabled(settings.activePostProcessConfig.isBuiltInDefault)
                if !PostProcessor.lastError.isEmpty {
                    Text(PostProcessor.lastError)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                if !postProcessMessage.isEmpty {
                    Text(postProcessMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var updatesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Updates")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
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
            Text("Vocabulary")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            configFolderHeader(message: $vocabMessage)
            HStack {
                TextField("Word", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                TextField("IPA, optional", text: $newIPA)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { addWord() }
                    .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Delete") { deleteSelectedVocab() }
                    .disabled(selectedVocab.isEmpty)
            }
            TextField("Search", text: $vocabSearch)
                .textFieldStyle(.roundedBorder)
            Table(filteredVocabulary, selection: $selectedVocab) {
                TableColumn("Word") { entry in
                    Text(entry.word)
                }
                TableColumn("IPA") { entry in
                    Text(entry.ipa.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }
            .onDeleteCommand { deleteSelectedVocab() }
            Text("Select a row and press Delete. Restart listening after changes. Files live in ~/.custom-dictation-config/vocabulary.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var commandsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Commands")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            configFolderHeader(message: $commandMessage)
            HStack {
                TextField("Say this", text: $newPhrase)
                    .textFieldStyle(.roundedBorder)
                Picker("Does", selection: $newCommandKind) {
                    ForEach(CustomCommandKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
                commandDetailField
                Button("Add") { addCommand() }
                    .disabled(!canAddCommand)
                Button("Delete") { deleteSelectedCommands() }
                    .disabled(selectedCommands.isEmpty || selectedCommands.allSatisfy { id in
                        settings.commands.first { $0.id == id }?.builtin == true
                    })
            }
            TextField("Search", text: $commandSearch)
                .textFieldStyle(.roundedBorder)
            Table(filteredCommands, selection: $selectedCommands) {
                TableColumn("Phrase") { command in
                    Text(command.title)
                }
                TableColumn("Action") { command in
                    Text(command.actionTitle)
                        .foregroundStyle(.secondary)
                }
                TableColumn("Kind") { command in
                    Text(command.builtin ? "Built-in" : "Custom")
                        .foregroundStyle(.secondary)
                }
            }
            .onDeleteCommand { deleteSelectedCommands() }
            Text("Built-in commands are JSON files too. Editing them does not change engine behavior beyond the phrases and match rules in the file. Select a custom row and press Delete.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var filteredVocabulary: [VocabEntry] {
        uniqueByID(settings.vocabulary.filter { entry in
            let q = vocabSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { return true }
            return entry.word.localizedCaseInsensitiveContains(q) || entry.ipa.joined().localizedCaseInsensitiveContains(q)
        })
    }

    private var filteredCommands: [CommandSpec] {
        uniqueByID(settings.commands.filter { command in
            let q = commandSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { return true }
            return command.title.localizedCaseInsensitiveContains(q)
                || command.actionTitle.localizedCaseInsensitiveContains(q)
                || command.phrases.joined(separator: " ").localizedCaseInsensitiveContains(q)
        })
    }

    private func uniqueByID<T: Identifiable>(_ items: [T]) -> [T] where T.ID: Hashable {
        var seen = Set<T.ID>()
        return items.filter { seen.insert($0.id).inserted }
    }

    @ViewBuilder
    private func configFolderHeader(message: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("~/.custom-dictation-config")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack {
                Button("Show folder") { ConfigFolder.revealInFinder() }
                Button("Export folder…") { exportConfigFolder() }
                Button("Import folder…") { importConfigFolder() }
                Button(importingVoiceControl ? "Importing…" : "Import Voice Control") {
                    importVoiceControl()
                }
                .disabled(importingVoiceControl)
                Button("Restore built-ins") {
                    ConfigFolder.restoreBuiltins()
                    store.reloadFromFolder()
                    settings = store.settings
                    commandMessage = "Restored built-in command files."
                }
            }
            DisclosureGroup("Folder format", isExpanded: $showFormat) {
                Text("One JSON file per command in commands/, one JSON file per word in vocabulary/. See README.md in the folder. Import replaces ~/.custom-dictation-config. You can also replace that folder yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !message.wrappedValue.isEmpty {
                Text(message.wrappedValue)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var commandDetailField: some View {
        switch newCommandKind {
        case .pasteText:
            TextField("Text to paste", text: $newPasteText)
                .textFieldStyle(.roundedBorder)
        case .shortcut:
            TextField("command shift s", text: $newShortcut)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140)
        case .openFile:
            HStack {
                Text(newFilePath.isEmpty ? "No file" : (newFilePath as NSString).lastPathComponent)
                    .foregroundStyle(newFilePath.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                Button("Choose…") { chooseCommandFile() }
            }
        }
    }

    private var diagnosticsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diagnostics")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Last heard: \(session.lastFinal.isEmpty ? "—" : session.lastFinal)")
            Text("Last route: \(session.lastRoute.isEmpty ? "—" : session.lastRoute)")
            ScrollView {
                Text(logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
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
        case .off, .suspended: return "Listening is off"
        case .listening: return "Listening"
        }
    }

    private var statusDetail: String {
        switch session.state {
        case .off:
            return "The microphone is off. Start listening, click the box below or another app, then speak."
        case .suspended:
            return "Start listening, click the box below or another app, then speak."
        case .listening:
            return "Click the box below or another app, then speak. Say “stop listening dictation” to stop."
        }
    }

    private enum AppSection: String, CaseIterable, Hashable {
        case listen
        case vocabulary
        case commands
        case postProcess
        case updates
        case diagnostics

        var title: String {
            switch self {
            case .listen: return "Listen"
            case .vocabulary: return "Vocabulary"
            case .commands: return "Commands"
            case .postProcess: return "Post-process"
            case .updates: return "Updates"
            case .diagnostics: return "Diagnostics"
            }
        }

        var icon: String {
            switch self {
            case .listen: return "mic.fill"
            case .vocabulary: return "text.book.closed"
            case .commands: return "command"
            case .postProcess: return "function"
            case .updates: return "arrow.down.circle"
            case .diagnostics: return "waveform.path.ecg"
            }
        }
    }

    private enum FinalizeMenu: Hashable {
        case tenths(Int)
        case custom
    }

    private enum KeyRepeatMenu: Hashable {
        case millis(Int)
        case custom
    }

    private enum LonePunctMenu: Hashable {
        case tenths(Int)
        case custom
    }

    private var finalizeMenu: FinalizeMenu {
        if finalizeUsesCustom { return .custom }
        if let tenths = AppSettings.finalizeDelayTenths(settings.finalizeDelaySeconds) {
            return .tenths(tenths)
        }
        return .custom
    }

    private var finalizeMenuBinding: Binding<FinalizeMenu> {
        Binding(
            get: { finalizeMenu },
            set: { choice in
                switch choice {
                case .tenths(let tenths):
                    finalizeUsesCustom = false
                    applyFinalizeDelay(Double(tenths) / 10)
                case .custom:
                    finalizeUsesCustom = true
            customFinalizeText = Self.finalizeFieldText(settings.finalizeDelaySeconds)
            customKeyRepeatText = Self.keyRepeatFieldText(settings.keyRepeatDelaySeconds)
                }
            }
        )
    }

    private var keyRepeatMenu: KeyRepeatMenu {
        if keyRepeatUsesCustom { return .custom }
        if let millis = AppSettings.keyRepeatDelayMillis(settings.keyRepeatDelaySeconds) {
            return .millis(millis)
        }
        return .custom
    }

    private var keyRepeatMenuBinding: Binding<KeyRepeatMenu> {
        Binding(
            get: { keyRepeatMenu },
            set: { choice in
                switch choice {
                case .millis(let millis):
                    keyRepeatUsesCustom = false
                    applyKeyRepeatDelay(Double(millis) / 1000)
                case .custom:
                    keyRepeatUsesCustom = true
            customKeyRepeatText = Self.keyRepeatFieldText(settings.keyRepeatDelaySeconds)
            customLonePunctText = Self.finalizeFieldText(settings.lonePunctuationDelaySeconds)
                }
            }
        )
    }

    private var lonePunctMenu: LonePunctMenu {
        if lonePunctUsesCustom { return .custom }
        if let tenths = AppSettings.lonePunctuationDelayTenths(settings.lonePunctuationDelaySeconds) {
            return .tenths(tenths)
        }
        return .custom
    }

    private var lonePunctMenuBinding: Binding<LonePunctMenu> {
        Binding(
            get: { lonePunctMenu },
            set: { choice in
                switch choice {
                case .tenths(let tenths):
                    lonePunctUsesCustom = false
                    applyLonePunctDelay(Double(tenths) / 10)
                case .custom:
                    lonePunctUsesCustom = true
            customLonePunctText = Self.finalizeFieldText(settings.lonePunctuationDelaySeconds)
            loadPostProcessDraft()
                }
            }
        )
    }

    private var microphoneBinding: Binding<String?> {
        Binding(
            get: { settings.microphoneUID },
            set: { uid in
                settings.microphoneUID = uid
                persist()
                if session.state == .listening {
                    Task { await session.startListening() }
                }
            }
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

    private var postProcessIDBinding: Binding<String> {
        Binding(
            get: { settings.activePostProcessID },
            set: { id in
                savePostProcessDraft()
                settings.activePostProcessID = id
                persist()
                loadPostProcessDraft()
            }
        )
    }

    private func loadPostProcessDraft() {
        let config = settings.activePostProcessConfig
        postProcessName = config.name
        postProcessScript = config.script
        postProcessMessage = config.isBuiltInDefault ? "Built-in Default. Duplicate to edit." : ""
    }

    private func savePostProcessDraft() {
        guard !settings.activePostProcessConfig.isBuiltInDefault else { return }
        let id = settings.activePostProcessID
        if let index = settings.postProcessConfigs.firstIndex(where: { $0.id == id }) {
            let name = postProcessName.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.postProcessConfigs[index].name = name.isEmpty ? "Untitled" : name
            settings.postProcessConfigs[index].script = postProcessScript
            persist()
            postProcessMessage = "Saved."
        }
    }

    private func duplicatePostProcess() {
        savePostProcessDraft()
        let source = settings.activePostProcessConfig
        let copy = PostProcessConfig(
            id: UUID().uuidString,
            name: source.name == "Default" ? "Default copy" : "\(source.name) copy",
            script: source.script
        )
        settings.postProcessConfigs.append(copy)
        settings.activePostProcessID = copy.id
        persist()
        loadPostProcessDraft()
    }

    private func newPostProcess() {
        savePostProcessDraft()
        let blank = PostProcessConfig(
            id: UUID().uuidString,
            name: "New",
            script: "function process(ctx) {\n  return ctx.text;\n}\n"
        )
        settings.postProcessConfigs.append(blank)
        settings.activePostProcessID = blank.id
        persist()
        loadPostProcessDraft()
    }

    private func deletePostProcess() {
        let id = settings.activePostProcessID
        guard id != PostProcessConfig.defaultID else { return }
        settings.postProcessConfigs.removeAll { $0.id == id }
        settings.activePostProcessID = PostProcessConfig.defaultID
        persist()
        loadPostProcessDraft()
    }

    private func persist() {
        _ = store.update { $0 = settings }
        settings = store.settings
        session.setFinalizeDelay(settings.finalizeDelaySeconds)
    }

    private func applyFinalizeDelay(_ seconds: Double) {
        settings.finalizeDelaySeconds = AppSettings.clampedFinalizeDelay(seconds)
        customFinalizeText = Self.finalizeFieldText(settings.finalizeDelaySeconds)
        persist()
    }

    private func applyCustomFinalizeDelay() {
        let parsed = Double(customFinalizeText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        applyFinalizeDelay(parsed ?? settings.finalizeDelaySeconds)
    }

    private func applyKeyRepeatDelay(_ seconds: Double) {
        settings.keyRepeatDelaySeconds = AppSettings.clampedKeyRepeatDelay(seconds)
        customKeyRepeatText = Self.keyRepeatFieldText(settings.keyRepeatDelaySeconds)
        persist()
    }

    private func applyCustomKeyRepeatDelay() {
        let parsed = Double(customKeyRepeatText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        applyKeyRepeatDelay(parsed ?? settings.keyRepeatDelaySeconds)
    }

    private func applyLonePunctDelay(_ seconds: Double) {
        settings.lonePunctuationDelaySeconds = AppSettings.clampedLonePunctuationDelay(seconds)
        customLonePunctText = Self.finalizeFieldText(settings.lonePunctuationDelaySeconds)
        persist()
    }

    private func applyCustomLonePunctDelay() {
        let parsed = Double(customLonePunctText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        applyLonePunctDelay(parsed ?? settings.lonePunctuationDelaySeconds)
    }

    private static func keyRepeatMenuLabel(millis: Int) -> String {
        if millis == 0 { return "None" }
        return "\(millis) ms"
    }

    private static func keyRepeatFieldText(_ seconds: Double) -> String {
        if seconds == 0 { return "0" }
        let trimmed = String(format: "%.3f", seconds)
        return trimmed.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }

    private static func finalizeMenuLabel(tenths: Int) -> String {
        if tenths == 0 { return "0 seconds" }
        if tenths % 10 == 0 { return "\(tenths / 10) seconds" }
        return String(format: "%.1f seconds", Double(tenths) / 10)
    }

    private static func finalizeFieldText(_ seconds: Double) -> String {
        if seconds == floor(seconds) { return String(Int(seconds)) }
        return String(format: "%g", seconds)
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        let ipaRaw = newIPA.trimmingCharacters(in: .whitespacesAndNewlines)
        let ipa = ipaRaw.isEmpty ? [] : [ipaRaw]
        settings.vocabulary.removeAll { $0.word.caseInsensitiveCompare(word) == .orderedSame }
        settings.vocabulary.append(VocabEntry(word: word, ipa: ipa))
        settings.vocabulary.sort { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        persist()
        newWord = ""
        newIPA = ""
        vocabMessage = "Added \(word). Restart listening to apply."
    }

    private func deleteSelectedVocab() {
        let ids = selectedVocab
        settings.vocabulary.removeAll { ids.contains($0.id) }
        persist()
        selectedVocab = []
        vocabMessage = "Removed \(ids.count) word(s)."
    }

    private var canAddCommand: Bool {
        let phrase = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return false }
        switch newCommandKind {
        case .pasteText:
            return !newPasteText.isEmpty
        case .shortcut:
            return parseShortcut(newShortcut) != nil
        case .openFile:
            return !newFilePath.isEmpty
        }
    }

    private func addCommand() {
        let phrase = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        var command = CommandSpec(
            id: "Custom.local.\(UUID().uuidString)",
            phrases: [phrase],
            action: {
                switch newCommandKind {
                case .pasteText: return .pasteText
                case .shortcut: return .shortcut
                case .openFile: return .openFile
                }
            }()
        )
        switch newCommandKind {
        case .pasteText:
            command.pasteText = newPasteText
        case .shortcut:
            guard let parsed = parseShortcut(newShortcut) else {
                commandMessage = "Could not parse that shortcut."
                return
            }
            command.keyCode = Int(parsed.keyCode)
            command.modifierFlags = nsModifiers(from: parsed.flags)
        case .openFile:
            command.filePath = newFilePath
            command.fileBookmark = newFileBookmark
        }
        let newNormalized = command.phrases.map(TranscriptNormalizer.normalize)
        settings.commands.removeAll { existing in
            guard !existing.builtin else { return false }
            return existing.phrases.contains { newNormalized.contains(TranscriptNormalizer.normalize($0)) }
        }
        settings.commands.append(command)
        persist()
        newPhrase = ""
        newPasteText = ""
        newShortcut = ""
        newFilePath = ""
        newFileBookmark = nil
        commandMessage = "Added command. Restart listening to apply."
    }

    private func deleteSelectedCommands() {
        let ids = selectedCommands
        settings.commands.removeAll { command in
            ids.contains(command.id) && !command.builtin
        }
        persist()
        selectedCommands = []
        commandMessage = "Removed selected custom commands."
    }

    private func chooseCommandFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        newFilePath = url.path
        newFileBookmark = try? url.bookmarkData(options: .minimalBookmark)
    }

    private func parseShortcut(_ text: String) -> KeyPressCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = TranscriptNormalizer.normalize(trimmed)
        let withPress = normalized.hasPrefix("press ") ? normalized : "press \(normalized)"
        return KeyPressGrammar.parse(withPress)
    }

    private func nsModifiers(from flags: CGEventFlags) -> UInt64 {
        var ns: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { ns.insert(.command) }
        if flags.contains(.maskShift) { ns.insert(.shift) }
        if flags.contains(.maskAlternate) { ns.insert(.option) }
        if flags.contains(.maskControl) { ns.insert(.control) }
        if flags.contains(.maskSecondaryFn) { ns.insert(.function) }
        return UInt64(ns.rawValue)
    }

    private func importVoiceControl() {
        importingVoiceControl = true
        vocabMessage = "Importing…"
        commandMessage = "Importing…"
        Task.detached {
            do {
                let result = try VoiceControlImporter.importFromThisMac()
                await MainActor.run {
                    let kept = settings.commands.filter { $0.id.hasPrefix("Custom.local.") || $0.builtin }
                    settings.vocabulary = result.vocabulary
                    settings.commands = kept + result.commands.map(CommandSpec.init)
                    persist()
                    importingVoiceControl = false
                    let summary = "Imported \(result.vocabulary.count) words and \(result.commands.count) commands."
                    vocabMessage = summary
                    commandMessage = summary
                }
            } catch {
                await MainActor.run {
                    importingVoiceControl = false
                    vocabMessage = error.localizedDescription
                    commandMessage = error.localizedDescription
                }
            }
        }
    }

    private func exportConfigFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder to copy ~/.custom-dictation-config into."
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let dest = dir.appendingPathComponent(ConfigFolder.folderName, isDirectory: true)
        do {
            try ConfigFolder.export(to: dest)
            commandMessage = "Exported to \(dest.path)"
            vocabMessage = commandMessage
        } catch {
            commandMessage = error.localizedDescription
            vocabMessage = error.localizedDescription
        }
    }

    private func importConfigFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Import"
        panel.message = "This replaces ~/.custom-dictation-config."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigFolder.importReplacing(from: url)
            store.reloadFromFolder()
            settings = store.settings
            commandMessage = "Imported folder."
            vocabMessage = "Imported folder."
        } catch {
            commandMessage = error.localizedDescription
            vocabMessage = error.localizedDescription
        }
    }
}
