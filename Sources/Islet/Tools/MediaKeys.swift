import AppKit
import AudioToolbox
import CoreAudio

/// Takes over the volume and brightness keys: changes the level itself and shows it in the notch
/// instead of the system pop-up. Event taps need Accessibility; without it this simply does nothing.
/// Keys it can't handle (an output without volume control, an external display) pass through to macOS.
@MainActor
final class MediaKeys {
    var onChange: ((Banner) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() {
        guard tap == nil else { return }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(1 << 14), // NX_SYSDEFINED: media and brightness keys
                                callback: { _, type, event, context in
                                    let keys = Unmanaged<MediaKeys>.fromOpaque(context!).takeUnretainedValue()
                                    return MainActor.assumeIsolated { keys.handle(type, event) }
                                },
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        guard let key = NSEvent(cgEvent: event), key.subtype.rawValue == 8 else { return pass }
        let code = (key.data1 & 0xFFFF_0000) >> 16
        let isDown = (key.data1 & 0xFF00) >> 8 == 0x0A
        // ⌥⇧ gives quarter steps, like macOS does.
        let step: Float = key.modifierFlags.contains([.option, .shift]) ? 1 / 64 : 1 / 16

        switch code {
        case 0, 1: // NX_KEYTYPE_SOUND_UP, NX_KEYTYPE_SOUND_DOWN
            guard let volume = Volume.level else { return pass }
            if isDown {
                let level = min(1, max(0, volume + (code == 0 ? step : -step)))
                Volume.level = level
                Volume.isMuted = false
                onChange?(.level(symbol: Self.speaker(level), value: Double(level)))
            }
            return nil
        case 7: // NX_KEYTYPE_MUTE
            guard let muted = Volume.isMuted, let level = Volume.level else { return pass }
            if isDown {
                Volume.isMuted = !muted
                onChange?(.level(symbol: muted ? Self.speaker(level) : "volume-cross-bold", value: muted ? Double(level) : 0))
            }
            return nil
        case 2, 3: // NX_KEYTYPE_BRIGHTNESS_UP, NX_KEYTYPE_BRIGHTNESS_DOWN
            guard let brightness = Brightness.level else { return pass }
            if isDown {
                let level = min(1, max(0, brightness + (code == 2 ? step : -step)))
                Brightness.level = level
                onChange?(.level(symbol: "sun-bold", value: Double(level)))
            }
            return nil
        default:
            return pass
        }
    }

    private static func speaker(_ level: Float) -> String {
        level == 0 ? "volume-cross-bold" : level < 0.34 ? "volume-small-bold" : level < 0.67 ? "volume-bold" : "volume-loud-bold"
    }
}

/// The default output device's volume, as the system's own keys change it.
enum Volume {
    private static var device: AudioObjectID? {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr ? id : nil
    }

    static var level: Float? {
        get {
            guard let device else { return nil }
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(device, &address) else { return nil }
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
        }
        set {
            guard let device, var value = newValue else { return }
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        }
    }

    static var isMuted: Bool? {
        get {
            guard let device else { return nil }
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var value = UInt32(0)
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value != 0 : nil
        }
        set {
            guard let device, let newValue else { return }
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var value = UInt32(newValue ? 1 : 0)
            AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }
}

/// The built-in display's brightness, through the private DisplayServices framework that the
/// system's brightness keys use. Unavailable (nil) on external displays.
enum Brightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private static let framework = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getBrightness = framework.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
    private static let setBrightness = framework.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }

    private static var builtIn: CGDirectDisplayID? {
        NSScreen.screens
            .compactMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
            .first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var level: Float? {
        get {
            guard let display = builtIn, let getBrightness else { return nil }
            var value: Float = 0
            return getBrightness(display, &value) == 0 ? value : nil
        }
        set {
            guard let display = builtIn, let setBrightness, let newValue else { return }
            _ = setBrightness(display, newValue)
        }
    }
}
