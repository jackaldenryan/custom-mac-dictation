import CoreAudio
import CustomDictationKit
import Foundation

// Hardware check for microphone stall recovery, on the built-in mic (so the
// headset in use is never touched). Changes the built-in mic's sample rate
// under a running capture, the change that silently stalls AVAudioEngine,
// and checks audio keeps arriving:
//   A. the format listener rebuilds capture,
//   B. with listeners off, the watchdog rebuilds it,
//   C. two starts at once build one capture.
// The session is paused (suspended), so nothing heard is typed or run.
//
//   CUSTOM_DICTATION_CONFIG=$(mktemp -d) swift run ProbeCaptureRecovery

guard ProcessInfo.processInfo.environment["CUSTOM_DICTATION_CONFIG"] != nil else {
    print("Set CUSTOM_DICTATION_CONFIG to a temporary folder")
    exit(2)
}
setvbuf(stdout, nil, _IOLBF, 0)

func builtInMic() -> (uid: String, id: AudioDeviceID)? {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
    for id in ids {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        if AudioObjectGetPropertyData(id, &a, 0, nil, &s, &value) == noErr,
           let uid = value?.takeUnretainedValue() as String?, uid == "BuiltInMicrophoneDevice" {
            return (uid, id)
        }
    }
    return nil
}

func rate(_ id: AudioDeviceID) -> Double {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var r: Double = 0
    var s = UInt32(MemoryLayout<Double>.size)
    AudioObjectGetPropertyData(id, &a, 0, nil, &s, &r)
    return r
}

func setRate(_ id: AudioDeviceID, _ value: Double) {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var r = value
    let status = AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Double>.size), &r)
    print("   set built-in mic to \(Int(value)) Hz (status \(status))")
}

func sleep(_ seconds: Double) async {
    try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
}

guard let mic = builtInMic() else {
    print("No built-in microphone")
    exit(2)
}
let original = rate(mic.id)
let other = original == 44100 ? 48000.0 : 44100.0
print("Built-in mic at \(Int(original)) Hz")

let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CUSTOM_DICTATION_CONFIG"]!)
let store = SettingsStore(url: folder.appendingPathComponent("app-settings.json"))
_ = store.update {
    $0.microphonePriority = [MicrophoneDevice(uid: mic.uid, name: "MacBook Pro Microphone")]
    $0.holdToTalk.enabled = false
    $0.diagnosticLogging = true
}
let session = ListeningSession(store: store)
var failures = 0

@MainActor func flowing(_ label: String, over seconds: Double) async -> Bool {
    let before = session.audioBufferCount
    await sleep(seconds)
    let got = session.audioBufferCount - before
    print("   \(label): \(got) buffers in \(seconds) s")
    return got >= Int(seconds * 5)
}

await session.startListening(persist: false)
session.suspend()
await sleep(4)
if await flowing("baseline", over: 2) == false { print("FAIL: no audio at all (microphone permission?)"); exit(1) }

print("A. Format listener")
let startsA = session.captureStartCount
setRate(mic.id, other)
// The watchdog can't act before 2 s of silence, so audio in the 0.8-1.8 s
// window after the change proves the listener rebuilt the capture.
await sleep(0.8)
let a = await flowing("0.8-1.8 s after switching to \(Int(other)) Hz", over: 1)
print(a && session.captureStartCount > startsA ? "   PASS: capture rebuilt by the format listener" : "   FAIL")
if !(a && session.captureStartCount > startsA) { failures += 1 }
setRate(mic.id, original)
await sleep(4)

print("B. Watchdog (format listeners off)")
AudioCapture.deviceListenersEnabled = false
await session.stopCompletely(persist: false)
await session.startListening(persist: false)
session.suspend()
await sleep(4)
_ = await flowing("before the change", over: 1)
let startsB = session.captureStartCount
setRate(mic.id, other)
let changedAt = Date()
var rebuiltAfter: Double?
for _ in 0..<40 {
    await sleep(0.25)
    if session.captureStartCount > startsB { rebuiltAfter = Date().timeIntervalSince(changedAt); break }
}
print("   rebuilt \(rebuiltAfter.map { String(format: "%.1f s", $0) } ?? "never") after the stall began")
await sleep(1)
let b = await flowing("after the stall", over: 3)
print(b && session.captureStartCount > startsB ? "   PASS: watchdog rebuilt the stalled capture" : "   FAIL")
if !(b && session.captureStartCount > startsB) { failures += 1 }
setRate(mic.id, original)
AudioCapture.deviceListenersEnabled = true
await sleep(4)

print("C. Two starts at once")
await session.stopCompletely(persist: false)
let startsC = session.captureStartCount
async let first: Void = session.startListening(persist: false)
async let second: Void = session.startListening(persist: false)
_ = await (first, second)
session.suspend()
let builtC = session.captureStartCount - startsC
print(builtC == 1 ? "   PASS: one capture" : "   FAIL: \(builtC) captures")
if builtC != 1 { failures += 1 }
_ = await flowing("audio", over: 2)

await session.stopCompletely(persist: false)
if rate(mic.id) != original { setRate(mic.id, original) }
print(failures == 0 ? "ProbeCaptureRecovery passed" : "ProbeCaptureRecovery FAILED (\(failures))")
exit(failures == 0 ? 0 : 1)
