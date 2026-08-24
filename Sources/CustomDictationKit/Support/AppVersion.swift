import Foundation

public enum AppVersion {
    public static let current: String = {
        if let fromBundle = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !fromBundle.isEmpty,
           fromBundle != "VERSION_PLACEHOLDER"
        {
            return fromBundle
        }
        return "0.1.0"
    }()

    public static func isRemoteNewer(_ remote: String, than local: String = current) -> Bool {
        compare(remote, local) == .orderedDescending
    }

    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parse(lhs)
        let right = parse(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a > b { return .orderedDescending }
            if a < b { return .orderedAscending }
        }
        return .orderedSame
    }

    private static func parse(_ raw: String) -> [Int] {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .compactMap { Int($0.split(separator: "-").first ?? "") }
    }
}
