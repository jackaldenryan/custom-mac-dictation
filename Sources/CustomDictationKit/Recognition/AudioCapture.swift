import AVFoundation
import CoreAudio
import CoreMedia
import Foundation

public struct MicrophoneDevice: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String { uid }
    public var uid: String
    public var name: String

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

/// Calls back on the main actor when microphones are plugged in or removed,
/// or the system default input changes.
public final class MicrophoneWatcher {
    private let block: AudioObjectPropertyListenerBlock
    private static let selectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice]

    public init(onChange: @escaping @Sendable @MainActor () -> Void) {
        block = { _, _ in
            Task { @MainActor in onChange() }
        }
        for selector in Self.selectors {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        }
    }

    deinit {
        for selector in Self.selectors {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

public final class AudioCapture: @unchecked Sendable {
    public let deviceUID: String?
    private let outputFormat: AVAudioFormat
    private let onBuffer: @Sendable (AVAudioPCMBuffer, CMTime) -> Void
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var framePosition: Int64 = 0
    private let timeBase: CMTime
    private let healthLock = NSLock()
    private var lastBuffer: Double?
    /// Monotonic time capture started (ProcessInfo.systemUptime).
    public private(set) var startedUptime: Double = 0
    /// Monotonic time of the last buffer handed on; nil before the first.
    public var lastBufferUptime: Double? { healthLock.withLock { lastBuffer } }
    /// Called once when the microphone changes format under the running
    /// engine or the engine stops itself (see CaptureHealth).
    public var onInterrupted: (@Sendable (String) -> Void)?
    /// Test hook: ProbeCaptureRecovery turns the device listeners off to
    /// prove the watchdog recovers on its own.
    nonisolated(unsafe) public static var deviceListenersEnabled = true
    private var watchedDevice: AudioDeviceID?
    private var startFormat: DeviceFormat?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var engineObserver: NSObjectProtocol?
    private var interrupted = false
    private let listenerQueue = DispatchQueue(label: "com.jackaldenryan.custom-mac-dictation.capture-device")
    private static let watchedSelectors: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
        (kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal),
        (kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput),
        (kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal),
    ]

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
        startedUptime = ProcessInfo.processInfo.systemUptime
        healthLock.withLock { lastBuffer = nil }
        let tapFormat = inputFormat
        input.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let usable = self.convert(buffer) ?? (self.converter == nil ? buffer : nil)
            guard let usable, usable.frameLength > 0 else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.healthLock.withLock { self.lastBuffer = now }
            let start = CMTimeAdd(
                self.timeBase,
                CMTime(value: self.framePosition, timescale: CMTimeScale(self.outputFormat.sampleRate))
            )
            self.framePosition += Int64(usable.frameLength)
            self.onBuffer(usable, start)
        }
        watchDevice()
    }

    /// Rebuild-worthy changes: the device's sample rate or input channels
    /// change, the device goes away, or the engine stops itself.
    private func watchDevice() {
        guard Self.deviceListenersEnabled else { return }
        let id = deviceUID.flatMap(Self.deviceID(for:)) ?? Self.defaultInputDeviceID()
        if let id {
            watchedDevice = id
            startFormat = Self.deviceFormat(id)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self, let id = self.watchedDevice, let started = self.startFormat else { return }
                let now = Self.deviceFormat(id)
                if CaptureHealth.formatChanged(started: started, now: now) {
                    self.interrupt("mic format changed: \(Int(started.sampleRate)) Hz \(started.inputChannels) ch -> \(Int(now.sampleRate)) Hz \(now.inputChannels) ch\(now.alive ? "" : ", device gone")")
                }
            }
            deviceListener = block
            for (selector, scope) in Self.watchedSelectors {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
                AudioObjectAddPropertyListenerBlock(id, &address, listenerQueue, block)
            }
        }
        engineObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self, !self.engine.isRunning else { return }
            self.interrupt("audio engine stopped after a configuration change")
        }
    }

    private func interrupt(_ reason: String) {
        let first = healthLock.withLock { () -> Bool in
            if interrupted { return false }
            interrupted = true
            return true
        }
        if first { onInterrupted?(reason) }
    }

    private func unwatchDevice() {
        if let id = watchedDevice, let block = deviceListener {
            for (selector, scope) in Self.watchedSelectors {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
                AudioObjectRemovePropertyListenerBlock(id, &address, listenerQueue, block)
            }
        }
        watchedDevice = nil
        deviceListener = nil
        if let observer = engineObserver { NotificationCenter.default.removeObserver(observer) }
        engineObserver = nil
    }

    static func deviceFormat(_ id: AudioDeviceID) -> DeviceFormat {
        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate: Double = 0
        var rateSize = UInt32(MemoryLayout<Double>.size)
        AudioObjectGetPropertyData(id, &rateAddress, 0, nil, &rateSize, &rate)
        var aliveAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var alive: UInt32 = 0
        var aliveSize = UInt32(MemoryLayout<UInt32>.size)
        let aliveStatus = AudioObjectGetPropertyData(id, &aliveAddress, 0, nil, &aliveSize, &alive)
        return DeviceFormat(sampleRate: rate, inputChannels: inputChannelCount(id), alive: aliveStatus == noErr && alive != 0)
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    public func stop() {
        unwatchDevice()
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

    /// The uid of the current system default input device.
    public static func defaultInputUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return stringProperty(id, kAudioDevicePropertyDeviceUID)
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
