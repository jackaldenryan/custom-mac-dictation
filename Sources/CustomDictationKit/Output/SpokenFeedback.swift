import AppKit
import AVFoundation

@MainActor
public final class SpokenFeedback {
    public static let shared = SpokenFeedback()
    private let synthesizer = AVSpeechSynthesizer()

    public func say(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.prefersAssistiveTechnologySettings = true
        synthesizer.speak(utterance)
    }
}
