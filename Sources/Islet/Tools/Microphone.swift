import CoreAudio
import Observation

/// Mutes the Mac's input for every app at once, the way a hardware mute switch would.
/// Inputs without a mute control get their volume set to zero instead, then restored.
@Observable @MainActor
final class Microphone {
    private(set) var isMuted = false
    @ObservationIgnored var onChange: ((Bool) -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var volumeBeforeMute: Float32?

    func start() {
        guard timer == nil else { return }
        refresh()
        // The input can be muted elsewhere (a meeting app, another device), so keep the indicator honest.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isMuted = false
    }

    func toggle() {
        guard let device = Self.inputDevice else { return }
        let mute = !isMuted
        if Self.set(UInt32(mute ? 1 : 0), selector: kAudioDevicePropertyMute, on: device) {
            // Done with the mute control.
        } else if mute {
            volumeBeforeMute = Self.get(Float32.self, selector: kAudioDevicePropertyVolumeScalar, on: device)
            _ = Self.set(Float32(0), selector: kAudioDevicePropertyVolumeScalar, on: device)
        } else {
            _ = Self.set(volumeBeforeMute ?? 0.75, selector: kAudioDevicePropertyVolumeScalar, on: device)
            volumeBeforeMute = nil
        }
        refresh()
        onChange?(isMuted)
    }

    private func refresh() {
        guard let device = Self.inputDevice else { isMuted = false; return }
        if let muted = Self.get(UInt32.self, selector: kAudioDevicePropertyMute, on: device) {
            isMuted = muted != 0
        } else {
            isMuted = volumeBeforeMute != nil
        }
    }

    // MARK: Core Audio

    private static var inputDevice: AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    private static func get<T: BitwiseCopyable>(_: T.Type, selector: AudioObjectPropertySelector, on device: AudioObjectID) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, value) == noErr ? value.pointee : nil
    }

    private static func set<T: BitwiseCopyable>(_ value: T, selector: AudioObjectPropertySelector, on device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }
}
