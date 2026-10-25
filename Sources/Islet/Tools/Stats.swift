import Darwin
import SwiftUI

/// CPU, memory and network, sampled every 2 seconds while the stats tab is open.
@Observable @MainActor
final class SystemStats {
    private(set) var cpu: Double?
    private(set) var memoryUsed: Double = 0 // bytes
    let memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    private(set) var download: Double = 0 // bytes per second
    private(set) var upload: Double = 0
    private(set) var battery: (percent: Int, onPower: Bool)?

    @ObservationIgnored private var lastTicks: (busy: UInt64, total: UInt64)?
    @ObservationIgnored private var lastBytes: [String: (received: UInt32, sent: UInt32)] = [:]
    @ObservationIgnored private var lastSample: Date?

    func sample() {
        let now = Date.now
        if let ticks = Self.cpuTicks() {
            if let lastTicks, ticks.total > lastTicks.total {
                cpu = Double(ticks.busy - lastTicks.busy) / Double(ticks.total - lastTicks.total)
            }
            lastTicks = ticks
        }
        memoryUsed = Self.memoryUsed() ?? memoryUsed
        let bytes = Self.interfaceBytes()
        if let lastSample, now > lastSample {
            let seconds = now.timeIntervalSince(lastSample)
            // The kernel's per-interface counters are 32-bit and wrap, so subtract with wrapping.
            let deltas = bytes.compactMap { name, value in lastBytes[name].map { (value.received &- $0.received, value.sent &- $0.sent) } }
            download = Double(deltas.reduce(0) { $0 + UInt64($1.0) }) / seconds
            upload = Double(deltas.reduce(0) { $0 + UInt64($1.1) }) / seconds
        }
        lastBytes = bytes
        lastSample = now
        battery = Alerts.battery()
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1), idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    /// "Memory Used" the way Activity Monitor counts it: app memory + wired + compressed.
    private static func memoryUsed() -> Double? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = UInt64(info.internal_page_count) - UInt64(info.purgeable_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        return Double(pages * UInt64(vm_kernel_page_size))
    }

    private static func interfaceBytes() -> [String: (received: UInt32, sent: UInt32)] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [:] }
        defer { freeifaddrs(first) }
        var bytes: [String: (received: UInt32, sent: UInt32)] = [:]
        for pointer in sequence(first: first, next: { $0?.pointee.ifa_next }) {
            guard let entry = pointer?.pointee, let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let data = entry.ifa_data?.assumingMemoryBound(to: if_data.self).pointee else { continue }
            let name = String(cString: entry.ifa_name)
            guard !name.hasPrefix("lo") else { continue } // loopback isn't network traffic
            bytes[name] = (data.ifi_ibytes, data.ifi_obytes)
        }
        return bytes
    }
}

struct StatsView: View {
    let stats: SystemStats
    let usage: Usage

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                Meter(name: "CPU", fraction: stats.cpu, value: stats.cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "")
                Meter(name: "Memory", fraction: stats.memoryUsed / stats.memoryTotal,
                      detail: "of \(Self.gigabytes(stats.memoryTotal))", value: Self.gigabytes(stats.memoryUsed))
            }
            HStack(spacing: 24) {
                if let battery = stats.battery {
                    Meter(name: "Battery", fraction: Double(battery.percent) / 100, warnsWhenFull: false,
                          detail: battery.onPower ? "on power" : "", value: "\(battery.percent)%")
                }
                Meter(name: "Network", fraction: nil, detail: "↓ \(Self.rate(stats.download))", value: "↑ \(Self.rate(stats.upload))")
            }
            if usage.showsAny {
                HStack(spacing: 24) {
                    if usage.showsClaude { Meter(name: "Claude", reading: usage.claude) }
                    if usage.showsCodex { Meter(name: "Codex", reading: usage.codex) }
                }
            }
        }
        .task {
            usage.refresh()
            while !Task.isCancelled {
                stats.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private static func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1f GB", bytes / 1_073_741_824)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }
}

/// A labeled level: name, optional detail, value, and a thin bar that turns orange near full.
struct Meter: View {
    let name: String
    var fraction: Double?
    var warnsWhenFull = true
    var detail = ""
    var value = ""
    var note: String?

    var body: some View {
        let level = min(1, max(0, fraction ?? 0))
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(name).foregroundStyle(Palette.graphite)
                Spacer(minLength: 4)
                if let note {
                    Text(note).foregroundStyle(Palette.ash)
                } else {
                    if !detail.isEmpty { Text(detail).foregroundStyle(Palette.ash) }
                    Text(value).fontWeight(.bold).foregroundStyle(Palette.paper)
                }
            }
            .font(Typeface.body)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(height: 13)
            Capsule()
                .fill(Palette.rail)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(warnsWhenFull && level >= 0.9 ? Palette.warning : Palette.paper)
                            .frame(width: geometry.size.width * level)
                    }
                }
                .frame(height: 3)
                .opacity(fraction == nil ? 0.5 : 1)
        }
        .frame(maxWidth: .infinity)
        .animation(Motion.easeOut(0.25), value: level)
        .accessibilityElement(children: .combine)
    }
}

extension Meter {
    /// A Claude or Codex plan limit.
    init(name: String, reading: UsageReading) {
        switch reading {
        case .loading:
            self.init(name: name, fraction: nil)
        case .unavailable(let note):
            self.init(name: name, fraction: nil, note: note)
        case .limit(let limit):
            self.init(name: name, fraction: limit.percent / 100,
                      detail: limit.resetsAt.map { "resets in " + Self.until($0) } ?? "",
                      value: "\(Int(limit.percent.rounded()))%")
        }
    }

    private static func until(_ date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
        if minutes >= 1440 { return "\(minutes / 1440)d \(minutes % 1440 / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}
