import AppKit
import Foundation

public struct AvailableUpdate: Sendable {
    public var version: String
    public var downloadURL: URL
    public var releaseURL: URL
}

public enum UpdateCheckResult: Sendable {
    case upToDate(String)
    case available(AvailableUpdate)
    case failed(String)
}

public enum UpdateChecker {
    public static let repo = "jackaldenryan/custom-mac-dictation"
    public static let latestAPI = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!

    public static func check() async -> UpdateCheckResult {
        do {
            var request = URLRequest(url: latestAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("CustomDictation/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                return .upToDate(AppVersion.current)
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remote = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            guard AppVersion.isRemoteNewer(remote) else {
                return .upToDate(AppVersion.current)
            }
            guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
                  let download = URL(string: asset.browserDownloadURL)
            else {
                return .failed("The latest release does not include a zip to install.")
            }
            return .available(AvailableUpdate(
                version: remote,
                downloadURL: download,
                releaseURL: URL(string: release.htmlURL) ?? download
            ))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    public static func install(_ update: AvailableUpdate) async throws {
        let (tempZip, _) = try await URLSession.shared.download(from: update.downloadURL)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("CustomDictationUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zipPath = work.appendingPathComponent("update.zip")
        try FileManager.default.copyItem(at: tempZip, to: zipPath)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-xk", zipPath.path, work.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw NSError(domain: "UpdateChecker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not unpack the update."])
        }

        guard let newApp = findApp(in: work) else {
            throw NSError(domain: "UpdateChecker", code: 2, userInfo: [NSLocalizedDescriptionKey: "The update zip did not contain an app."])
        }

        let currentApp = Bundle.main.bundleURL
        guard currentApp.pathExtension == "app" else {
            throw NSError(domain: "UpdateChecker", code: 3, userInfo: [NSLocalizedDescriptionKey: "Install Custom Dictation as an app first, then use Check for Updates."])
        }

        let scriptURL = work.appendingPathComponent("install.sh")
        let script = """
        #!/bin/bash
        set -euo pipefail
        pid=\(ProcessInfo.processInfo.processIdentifier)
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        rm -rf "\(currentApp.path)"
        /usr/bin/ditto "\(newApp.path)" "\(currentApp.path)"
        /usr/bin/xattr -cr "\(currentApp.path)" || true
        /usr/bin/open "\(currentApp.path)"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let installer = Process()
        installer.executableURL = scriptURL
        try installer.run()
        await MainActor.run {
            NSApp.terminate(nil)
        }
    }

    private static func findApp(in folder: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let item = enumerator?.nextObject() as? URL {
            if item.pathExtension == "app" { return item }
        }
        return nil
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}
