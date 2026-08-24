import AppKit
import Foundation

public enum DiagnosticLog {
    public static var fileURL: URL {
        let folder = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/CustomDictation", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("dictation.log")
    }

    public static func line(_ message: String) {
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
        let entry = "[\(stamp)] \(message)\n"
        queue.async {
            let url = fileURL
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            if let data = entry.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        }
        fputs(entry, stderr)
    }

    public static func tail(maxBytes: Int = 32_000) -> String {
        guard let data = try? Data(contentsOf: fileURL) else { return "No log yet." }
        if data.count <= maxBytes {
            return String(decoding: data, as: UTF8.self)
        }
        return String(decoding: data.suffix(maxBytes), as: UTF8.self)
    }

    public static func revealInFinder() {
        let url = fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            line("Log file created.")
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static let queue = DispatchQueue(label: "com.jackaldenryan.custom-mac-dictation.log")
}
