import Foundation

public enum SelectionTransformError: Error {
    case nothingSelected
}

public enum SelectionTransform {
    public enum Kind {
        case capitalize
        case uppercase
        case lowercase
    }

    public static func apply(_ kind: Kind) throws {
        let client = DictationTextInput.current
        guard let raw = client.selectedString(), !raw.isEmpty else {
            throw SelectionTransformError.nothingSelected
        }
        client.insertText(transform(raw, kind: kind))
    }

    private static func transform(_ raw: String, kind: Kind) -> String {
        switch kind {
        case .capitalize:
            return raw.localizedCapitalized
        case .uppercase:
            return raw.localizedUppercase
        case .lowercase:
            return raw.localizedLowercase
        }
    }
}
