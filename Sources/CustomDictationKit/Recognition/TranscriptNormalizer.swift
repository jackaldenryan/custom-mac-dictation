import Foundation

public enum TranscriptNormalizer {
    public static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.punctuationCharacters.contains(scalar) { return " " }
            return Character(scalar)
        }
        let collapsed = String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isLonePunctuation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let scalar = trimmed.unicodeScalars.first else { return false }
        return CharacterSet.punctuationCharacters.contains(scalar)
    }
}
