import Foundation
import Observation

/// Up to three cities' times, shown in Home's status row. Chosen in Settings.
@Observable @MainActor
final class WorldClock {
    static let shared = WorldClock()
    static let limit = 3
    static let defaults = ["America/New_York", "Europe/London", "Asia/Tokyo"]

    var zones: [String] {
        didSet { UserDefaults.standard.set(zones, forKey: "worldClock") }
    }

    private init() {
        zones = UserDefaults.standard.stringArray(forKey: "worldClock") ?? Self.defaults
    }

    /// "America/Los_Angeles" -> "Los Angeles".
    nonisolated static func city(_ identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier).replacingOccurrences(of: "_", with: " ")
    }

    nonisolated static func time(_ identifier: String, at date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: identifier) ?? .current
        return date.formatted(style)
    }
}
