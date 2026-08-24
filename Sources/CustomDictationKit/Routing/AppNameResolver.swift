import AppKit
import Foundation

public struct ResolvedApp: Equatable, Sendable {
    public var url: URL
    public var name: String
    public var bundleIdentifier: String?
    public var running: NSRunningApplication?

    public init(url: URL, name: String, bundleIdentifier: String?, running: NSRunningApplication?) {
        self.url = url
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.running = running
    }
}

public enum AppNameResolver {
    public static func resolve(_ spoken: String) -> ResolvedApp? {
        let query = tokens(spoken)
        guard !query.isEmpty else { return nil }

        var candidates: [(ResolvedApp, Int)] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let name = app.localizedName ?? app.bundleIdentifier ?? ""
            let score = overlap(query, tokens(name) + tokens(app.bundleIdentifier ?? ""))
            if score > 0, let url = app.bundleURL {
                candidates.append((
                    ResolvedApp(url: url, name: name, bundleIdentifier: app.bundleIdentifier, running: app),
                    score
                ))
            }
        }

        let searchRoots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        for root in searchRoots {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in items where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                let score = overlap(query, tokens(name))
                if score > 0 {
                    let bundle = Bundle(url: url)
                    candidates.append((
                        ResolvedApp(
                            url: url,
                            name: name,
                            bundleIdentifier: bundle?.bundleIdentifier,
                            running: NSWorkspace.shared.runningApplications.first { $0.bundleURL == url }
                        ),
                        score
                    ))
                }
            }
        }

        return candidates.max { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.name.count > rhs.0.name.count
        }?.0
    }

    public static func matchesNeverQuit(app: ResolvedApp, neverQuitNames: [String]) -> Bool {
        let hay = tokens(app.name) + tokens(app.bundleIdentifier ?? "") + tokens(app.url.deletingPathExtension().lastPathComponent)
        return neverQuitNames.contains { name in
            let needle = tokens(name)
            return !needle.isEmpty && needle.allSatisfy { hay.contains($0) }
        }
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: ".app", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0 != "com" && $0 != "app" }
    }

    private static func overlap(_ query: [String], _ candidate: [String]) -> Int {
        query.filter { candidate.contains($0) }.count
    }
}
