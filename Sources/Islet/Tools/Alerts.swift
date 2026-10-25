import AppKit
import IOBluetooth
import IOKit.ps

/// Battery when you plug in or drop to 20% and 10%, and headphone battery when they connect.
@MainActor
final class Alerts: NSObject {
    var onBanner: ((Banner) -> Void)?
    private var powerSource: CFRunLoopSource?
    private var wasOnPower: Bool?
    private var lastPercent: Int?
    private var connections: IOBluetoothUserNotification?

    func start() {
        guard powerSource == nil else { return }
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            MainActor.assumeIsolated { Unmanaged<Alerts>.fromOpaque(context!).takeUnretainedValue().powerChanged() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerChanged(announce: false)
        connections = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    func stop() {
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        powerSource = nil
        connections?.unregister()
        connections = nil
    }

    /// The internal battery's charge and whether it's plugged in; nil on Macs without one.
    static func battery() -> (percent: Int, onPower: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return (current * 100 / max, description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }

    static func shouldWarn(from previous: Int, to percent: Int) -> Bool {
        [20, 10].contains { previous > $0 && percent <= $0 }
    }

    private func powerChanged(announce: Bool = true) {
        guard let battery = Self.battery() else { return }
        defer { (wasOnPower, lastPercent) = (battery.onPower, battery.percent) }
        guard announce else { return }
        if battery.onPower, wasOnPower == false {
            onBanner?(.battery(percent: battery.percent, charging: true))
        } else if !battery.onPower, let lastPercent, Self.shouldWarn(from: lastPercent, to: battery.percent) {
            onBanner?(.battery(percent: battery.percent, charging: false))
        }
    }

    @objc private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard device.deviceClassMajor == BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio) else { return }
        let name = device.name ?? "Headphones"
        // AirPods report their battery a moment after connecting.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.onBanner?(.headphones(name: name, battery: Self.budBattery(device)))
        }
    }

    /// The lower earbud's charge. These IOBluetoothDevice properties are undocumented; AirPods and
    /// Beats fill them in, other headphones don't have them (checked before reading), and 0 means unknown.
    private static func budBattery(_ device: IOBluetoothDevice) -> Int? {
        ["batteryPercentLeft", "batteryPercentRight", "batteryPercentSingle"]
            .filter { device.responds(to: NSSelectorFromString($0)) }
            .compactMap { (device.value(forKey: $0) as? NSNumber)?.intValue }
            .filter { $0 > 0 }
            .min()
    }
}
