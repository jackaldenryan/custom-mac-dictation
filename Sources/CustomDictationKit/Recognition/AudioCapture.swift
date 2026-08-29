import AVFoundation
import CoreAudio
import CoreMedia
import Foundation

public struct MicrophoneDevice: Identifiable, Equatable, Sendable {
    public var id: String { uid }
    public var uid: String
    public var name: String
}

public final class AudioCapture {
    public let deviceUID: String?
    private let outputFormat: AVAudioFormat
    private let onBuffer: @Sendable (AVAudioPCMBuffer, CMTime) -> Void
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var framePosition: Int64 = 0
    private let timeBase: CMTime

    public init(
        deviceUID: String?,
        outputFormat: AVAudioFormat?,
        timeBase: CMTime = .zero,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer, CMTime) -> Void
    ) {
        self.deviceUID = deviceUID
        self.outputFormat = outputFormat ?? AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        self.timeBase = timeBase
        self.onBuffer = onBuffer
    }

    public func start() throws {
        let input = engine.inputNode
        if let uid = deviceUID {
            try Self.selectEngineInput(input, uid: uid)
        }

        engine.prepare()
        try engine.start()

        let inputFormat = input.inputFormat(forBus: 0)
        DiagnosticLog.line(
            "Audio start uid=\(deviceUID ?? "default") input=\(Self.describe(inputFormat)) output=\(Self.describe(outputFormat))"
        )
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(
                domain: "AudioCapture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone opened with no usable sample rate."]
            )
        }

        if inputFormat.sampleRate != outputFormat.sampleRate || inputFormat.channelCount != outputFormat.channelCount {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            if converter == nil {
                DiagnosticLog.line("Audio converter failed for \(Self.describe(inputFormat)) -> \(Self.describe(outputFormat))")
            }
        } else {
            converter = nil
        }

        framePosition = 0
        let tapFormat = inputFormat
        input.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let usable = self.convert(buffer) ?? (self.converter == nil ? buffer : nil)
            guard let usable, usable.frameLength > 0 else { return }
            let start = CMTimeAdd(
                self.timeBase,
                CMTime(value: self.framePosition, timescale: CMTimeScale(self.outputFormat.sampleRate))
            )
            self.framePosition += Int64(usable.frameLength)
            self.onBuffer(usable, start)
        }
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        framePosition = 0
    }

    public static func listMicrophones() -> [MicrophoneDevice] {
        var devices: [MicrophoneDevice] = []
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return devices
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids) == noErr else {
            return devices
        }
        for id in ids {
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var configSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(id, &inputAddress, 0, nil, &configSize) != noErr { continue }
            let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(configSize), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { raw.deallocate() }
            if AudioObjectGetPropertyData(id, &inputAddress, 0, nil, &configSize, raw) != noErr { continue }
            let list = raw.assumingMemoryBound(to: AudioBufferList.self)
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            let channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard channels > 0 else { continue }
            guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, kAudioDevicePropertyDeviceNameCFString)
            else { continue }
            devices.append(MicrophoneDevice(uid: uid, name: name))
        }
        return devices
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var consumed = false
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        if let error {
            DiagnosticLog.line("Audio convert error: \(error.localizedDescription)")
            return nil
        }
        return out
    }

    private static func selectEngineInput(_ input: AVAudioInputNode, uid: String) throws {
        guard let deviceID = deviceID(for: uid) else {
            DiagnosticLog.line("Mic uid \(uid) not found; using system input")
            return
        }
        guard let audioUnit = input.audioUnit else {
            DiagnosticLog.line("Input node has no audio unit; falling back to system default input")
            try selectSystemInputDevice(uid: uid)
            return
        }
        var id = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            size
        )
        if status != noErr {
            DiagnosticLog.line("Set input device failed (\(status)); falling back to system default")
            try selectSystemInputDevice(uid: uid)
        }
    }

    private static func selectSystemInputDevice(uid: String) throws {
        guard let deviceID = deviceID(for: uid) else { return }
        var id = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &id)
    }

    private static func deviceID(for uid: String) -> AudioDeviceID? {
        listDeviceIDs().first { stringProperty($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    private static func listDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }
        return ids
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize) == noErr else { return nil }
        var cfString: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &cfString) == noErr {
            return cfString?.takeUnretainedValue() as String?
        }
        return nil
    }

    private static func describe(_ format: AVAudioFormat) -> String {
        "\(format.sampleRate)Hz ch=\(format.channelCount) \(format.commonFormat.rawValue)"
    }
}
