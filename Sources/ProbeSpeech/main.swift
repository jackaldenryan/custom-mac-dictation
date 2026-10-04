import AVFoundation
import CustomDictationKit
import Foundation
import Speech

// Transcribe an audio file with the app's DictationTranscriber setup, with
// Apple's automatic punctuation on or off, and print every final result.
//
//   say -o /tmp/p.wav --file-format=WAVE --data-format=LEI16@16000 "hello comma how are you question mark"
//   swift run ProbeSpeech /tmp/p.wav --no-auto-punctuation
//
// Used to check that spoken punctuation still works with auto punctuation off.

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: ProbeSpeech <audio file> [--no-auto-punctuation]\n", stderr)
    exit(2)
}
let url = URL(fileURLWithPath: args[1])
let auto = !args.contains("--no-auto-punctuation")

let locale = Locale(identifier: "en_US")
let preset = DictationTranscriber.Preset.progressiveLongDictation
let options = TranscriberOptions.transcription(preset: preset, autoPunctuation: auto)
print("preset options: \(preset.transcriptionOptions)")
print("auto punctuation: \(auto) -> options: \(options)")

let transcriber = DictationTranscriber(
    locale: locale,
    contentHints: preset.contentHints,
    transcriptionOptions: options,
    reportingOptions: TranscriberOptions.reporting(preset: preset),
    attributeOptions: []
)
if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
    try await request.downloadAndInstall()
}
let file = try AVAudioFile(forReading: url)
let analyzer = SpeechAnalyzer(modules: [transcriber])
let collector = Task {
    var finals: [String] = []
    for try await result in transcriber.results where result.isFinal {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { finals.append(text) }
    }
    return finals
}
if let last = try await analyzer.analyzeSequence(from: file) {
    try await analyzer.finalizeAndFinish(through: last)
} else {
    await analyzer.cancelAndFinishNow()
}
let finals = try await collector.value
for (i, text) in finals.enumerated() {
    print("final[\(i)]: \(String(reflecting: text))")
}
print("joined: \(String(reflecting: finals.joined(separator: " ")))")
