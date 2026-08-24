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
        let cleaned = stripLeadingArticle(TranscriptNormalizer.normalize(spoken))
        let query = tokens(cleaned)
        guard !query.isEmpty else { return nil }

        var candidates: [(ResolvedApp, Int)] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let name = app.localizedName ?? app.bundleIdentifier ?? ""
            let score = scoreMatch(query, tokens(name))
            if score > 0, let url = app.bundleURL {
                candidates.append((
                    ResolvedApp(url: url, name: name, bundleIdentifier: app.bundleIdentifier, running: app),
                    score
                ))
            }
        }

        for app in discoveredApps() {
            let score = scoreMatch(query, tokens(app.name))
            if score > 0 {
                candidates.append((
                    ResolvedApp(
                        url: app.url,
                        name: app.name,
                        bundleIdentifier: app.bundleIdentifier,
                        running: runningApp(bundleIdentifier: app.bundleIdentifier, url: app.url)
                    ),
                    score
                ))
            }
        }

        return candidates.max { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.name.count > rhs.0.name.count
        }?.0
    }

    public static func commandPhrases() -> [String] {
        var phrases: [String] = []
        var seen = Set<String>()
        for app in discoveredApps() {
            let names = spokenVariants(app.name)
            for name in names {
                let key = name.lowercased()
                guard seen.insert(key).inserted else { continue }
                phrases.append("open \(name)")
                phrases.append("quit \(name)")
            }
        }
        return phrases
    }

    public static func runningApp(bundleIdentifier: String?, url: URL?) -> NSRunningApplication? {
        if let bundleIdentifier {
            if let match = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                return match
            }
        }
        if let url {
            let standardized = url.standardizedFileURL
            return NSWorkspace.shared.runningApplications.first {
                $0.bundleURL?.standardizedFileURL == standardized
            }
        }
        return nil
    }

    public static func discoveredApps() -> [ResolvedApp] {
        var byURL: [URL: ResolvedApp] = [:]

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let url = app.bundleURL else { continue }
            let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
            byURL[url.standardizedFileURL] = ResolvedApp(
                url: url,
                name: name,
                bundleIdentifier: app.bundleIdentifier,
                running: app
            )
        }

        for url in applicationURLs() {
            let key = url.standardizedFileURL
            if byURL[key] != nil { continue }
            let bundle = Bundle(url: url)
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            byURL[key] = ResolvedApp(
                url: url,
                name: name,
                bundleIdentifier: bundle?.bundleIdentifier,
                running: runningApp(bundleIdentifier: bundle?.bundleIdentifier, url: url)
            )
        }

        return Array(byURL.values)
    }

    private static func spokenVariants(_ name: String) -> [String] {
        let parts = tokens(name)
        guard !parts.isEmpty else { return [] }
        var variants = [parts.joined(separator: " ")]
        if parts.count > 1, let last = parts.last {
            variants.append(last)
        }
        return variants
    }

    private static func applicationURLs() -> [URL] {
        let searchRoots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var urls: [URL] = []
        for root in searchRoots {
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for item in items {
                if item.pathExtension == "app" {
                    urls.append(item)
                    continue
                }
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory),
                      isDirectory.boolValue
                else { continue }
                guard let nested = try? FileManager.default.contentsOfDirectory(
                    at: item,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }
                urls.append(contentsOf: nested.filter { $0.pathExtension == "app" })
            }
        }
        return urls
    }

    private static func stripLeadingArticle(_ text: String) -> String {
        if text.hasPrefix("the ") { return String(text.dropFirst(4)) }
        return text
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: ".app", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0 != "com" && $0 != "app" }
    }

    private static func scoreMatch(_ query: [String], _ candidate: [String]) -> Int {
        if query.isEmpty || candidate.isEmpty { return 0 }
        if query == candidate { return 100 }
        if query.joined() == candidate.joined() { return 90 }
        let allPresent = query.allSatisfy { token in
            candidate.contains { candidateToken in
                candidateToken == token || candidateToken.hasPrefix(token) || token.hasPrefix(candidateToken)
            }
        }
        if allPresent {
            return 50 + (query.count * 10)
        }
        let exactOverlap = query.filter { candidate.contains($0) }.count
        if exactOverlap > 0 { return exactOverlap * 10 }
        return 0
    }
}
