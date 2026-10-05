import Foundation

/// Built-in spoken emoji: "<name> emoji" anywhere in dictation becomes the
/// emoji ("thanks prayer hands emoji" -> "thanks 🙏"). Not a command in the
/// Commands list; it runs on every transcript before the post-process, so
/// it works alone or mid-sentence, live and final alike. Only phrases
/// ending in "emoji" change, so ordinary words are never replaced.
public enum EmojiPhrases {
    /// Spoken names (any of them) -> emoji. Add aliases for how Apple hears
    /// a name ("check mark" vs "checkmark").
    public static let table: [(names: [String], emoji: String)] = [
        (["raised hands", "raising hands", "hands raised", "hands up", "hands"], "🙌"),
        (["green check mark", "green checkmark", "green check", "check mark", "checkmark", "check"], "✅"),
        (["prayer hands", "praying hands", "prayer", "pray", "thank you hands"], "🙏"),
        (["slight smile", "slightly smiling", "slightly smiling face", "slight smile face", "small smile"], "🙂"),
        (["surprised face", "surprised", "open mouth", "shocked face"], "😮"),
        (["laugh cry", "laughing crying", "laugh crying", "crying laughing", "cry laughing", "tears of joy", "laughing"], "😂"),
        (["thumbs up", "thumb up"], "👍"),
        (["thumbs down", "thumb down"], "👎"),
        (["red heart", "heart"], "❤️"),
        (["fire", "flame"], "🔥"),
        (["party popper", "party", "tada", "celebration"], "🎉"),
        (["smiley face", "smiley", "big smile", "grinning face", "grinning"], "😃"),
        (["blush", "blushing", "smiling face", "smile"], "😊"),
        (["grin", "beaming face"], "😁"),
        (["sweat smile", "nervous laugh"], "😅"),
        (["wink", "winking face", "winking"], "😉"),
        (["upside down face", "upside down smile", "upside down"], "🙃"),
        (["thinking face", "thinking"], "🤔"),
        (["eyes"], "👀"),
        (["clapping hands", "clap", "clapping"], "👏"),
        (["waving hand", "wave", "waving"], "👋"),
        (["ok hand", "okay hand"], "👌"),
        (["flexed biceps", "muscle", "flex", "strong arm"], "💪"),
        (["rocket"], "🚀"),
        (["hundred points", "hundred", "100"], "💯"),
        (["sparkles", "sparkle"], "✨"),
        (["star"], "⭐"),
        (["crying face", "crying", "sad face", "sad"], "😢"),
        (["loudly crying", "sobbing"], "😭"),
        (["red x", "cross mark", "x mark"], "❌"),
        (["warning", "warning sign"], "⚠️"),
        (["face palm", "facepalm"], "🤦"),
        (["shrug", "shrugging"], "🤷"),
        (["heart eyes", "heart eyes face"], "😍"),
        (["sunglasses", "cool face"], "😎"),
        (["skull"], "💀"),
        (["salute", "saluting face"], "🫡"),
    ]

    /// Longest names first, so "green check mark" wins over "check mark".
    private static let patterns: [(NSRegularExpression, String)] = {
        var entries: [(String, String)] = []
        for row in table {
            for name in row.names { entries.append((name, row.emoji)) }
        }
        entries.sort { $0.0.count > $1.0.count }
        return entries.compactMap { name, emoji in
            let words = name.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
            let pattern = "(?<![\\p{L}\\p{N}])" + words.joined(separator: "[\\s-]+") + "\\s+emojis?(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            return (regex, emoji)
        }
    }()

    public static func replace(_ text: String) -> String {
        guard text.range(of: "emoji", options: .caseInsensitive) != nil else { return text }
        var out = text
        for (regex, emoji) in patterns {
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: emoji))
        }
        return out
    }
}
