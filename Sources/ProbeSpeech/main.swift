import AVFoundation
import CoreMedia
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
// --detector: add the SpeechDetector module the app used before Oct 7, to
// compare finals with and without voice-activity detection.
let useDetector = args.contains("--detector")

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
let modules: [any SpeechModule] = useDetector
    ? [SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: false), transcriber]
    : [transcriber]
print("detector: \(useDetector)")
let analyzer = SpeechAnalyzer(modules: modules)
let collector = Task {
    var finals: [String] = []
    for try await result in transcriber.results {
        guard result.isFinal else {
            if args.contains("--partials") { print("partial: \(String(result.text.characters))") }
            fflush(stdout)
            continue
        }
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { finals.append(text) }
    }
    return finals
}
if args.contains("--realtime") {
    // Feed the file at real-time pace in 1024-frame buffers, like the app's
    // live microphone capture.
    setvbuf(stdout, nil, _IOLBF, 0)
    let format = file.processingFormat
    guard let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
        fatalError("no analyzer format")
    }
    try await analyzer.prepareToAnalyze(in: target)
    guard let converter = AVAudioConverter(from: format, to: target) else { fatalError("no converter") }
    let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
    try await analyzer.start(inputSequence: stream)
    var position: AVAudioFramePosition = 0
    var outFrames: Int64 = 0
    while position < file.length {
        let count = AVAudioFrameCount(min(1024, file.length - position))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { break }
        try file.read(into: buffer, frameCount: count)
        let capacity = AVAudioFrameCount(Double(count) * target.sampleRate / format.sampleRate) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { break }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        let start = CMTime(value: CMTimeValue(outFrames), timescale: CMTimeScale(target.sampleRate))
        continuation.yield(AnalyzerInput(buffer: out, bufferStartTime: start))
        outFrames += Int64(out.frameLength)
        position += AVAudioFramePosition(buffer.frameLength)
        try await Task.sleep(for: .seconds(Double(buffer.frameLength) / format.sampleRate))
    }
    try await Task.sleep(for: .seconds(2))
    continuation.finish()
    try await analyzer.finalizeAndFinishThroughEndOfInput()
} else if let last = try await analyzer.analyzeSequence(from: file) {
    try await analyzer.finalizeAndFinish(through: last)
} else {
    await analyzer.cancelAndFinishNow()
}
let finals = try await collector.value
for (i, text) in finals.enumerated() {
    print("final[\(i)]: \(String(reflecting: text))")
}
print("joined: \(String(reflecting: finals.joined(separator: " ")))")
