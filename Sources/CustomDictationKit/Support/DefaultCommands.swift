import Foundation

enum DefaultCommands {
    static func load() -> [CommandSpec] {
        for directory in directories() {
            let loaded = load(from: directory)
            if !loaded.isEmpty { return loaded }
        }
        return []
    }

    private static func directories() -> [URL] {
        var urls: [URL] = []
        if let url = Bundle.main.url(forResource: "default-commands", withExtension: nil) {
            urls.append(url)
        }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Defaults/commands", isDirectory: true)
        if FileManager.default.fileExists(atPath: source.path) {
            urls.append(source)
        }
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: "default-commands", withExtension: nil) {
                urls.append(url)
            }
            if let root = bundle.resourceURL?.appendingPathComponent("Defaults/commands", isDirectory: true),
               FileManager.default.fileExists(atPath: root.path) {
                urls.append(root)
            }
        }
        return urls
    }

    private static func load(from directory: URL) -> [CommandSpec] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" })
        else { return [] }
        var loaded: [CommandSpec] = []
        for url in files {
            guard let spec = try? JSONDecoder().decode(CommandSpec.self, from: Data(contentsOf: url)) else { continue }
            loaded.append(spec)
        }
        return loaded.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }
}
