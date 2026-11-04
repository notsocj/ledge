import Foundation

/// Jolpica publishes schedules and classified results, not a live race feed.
struct F1Session: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let date: String
    let start: Date?

    /// Date-only sessions keep their published calendar day in every time zone.
    func dayLabel(timeZone: TimeZone = .current) -> String {
        guard let value = start ?? F1Dates.day(date) else { return date }
        var style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = start == nil ? F1Dates.utc : timeZone
        return value.formatted(style)
    }

    func timeLabel(timeZone: TimeZone = .current) -> String {
        guard let start else { return "Time TBC" }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return start.formatted(style)
    }
}

struct F1Race: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(season)-\(round)" }
    let season: Int
    let round: Int
    let name: String
    let circuit: String
    let date: String
    let start: Date?
    let sessions: [F1Session]

    var shortName: String { name.replacingOccurrences(of: " Grand Prix", with: "") }
    var sortDate: Date { start ?? F1Dates.day(date) ?? .distantFuture }

    func isUpcoming(at now: Date) -> Bool {
        if let start { return start > now }
        // A missing time cannot establish that a race has started.
        return date >= F1Dates.dayString(now)
    }
}

struct F1PodiumDriver: Codable, Equatable, Identifiable, Sendable {
    var id: Int { position }
    let position: Int
    let name: String
    let code: String
    let team: String
}

struct F1Podium: Codable, Equatable, Sendable {
    let race: F1Race
    let drivers: [F1PodiumDriver]
}

struct F1Snapshot: Codable, Equatable, Sendable {
    let races: [F1Race]
    let latestPodium: F1Podium?
    let fetchedAt: Date

    /// Once a scheduled start passes, wait briefly for results without claiming a race is live.
    func pendingRace(at now: Date) -> F1Race? {
        races.filter { race in
            guard let start = race.start, start <= now,
                  now.timeIntervalSince(start) < 24 * 60 * 60 else { return false }
            guard let podium = latestPodium else { return true }
            return race.season > podium.race.season ||
                (race.season == podium.race.season && race.round > podium.race.round)
        }.max { $0.sortDate < $1.sortDate }
    }

    func weekend(at now: Date) -> F1Race? {
        pendingRace(at: now) ?? races.filter { $0.isUpcoming(at: now) }.min { $0.sortDate < $1.sortDate }
    }

    func countdown(at now: Date) -> String {
        if pendingRace(at: now) != nil { return "Results pending" }
        guard let race = weekend(at: now) else { return "Schedule TBC" }
        guard let start = race.start else { return "Time TBC" }
        let minutes = max(1, Int(ceil(start.timeIntervalSince(now) / 60)))
        if minutes >= 24 * 60 { return "\(minutes / (24 * 60))d \((minutes / 60) % 24)h" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

enum F1Dates {
    static let utc = TimeZone(secondsFromGMT: 0)!

    static func start(date: String, time: String?) -> Date? {
        guard let time, !time.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        if let value = formatter.date(from: "\(date)T\(time)") { return value }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: "\(date)T\(time)")
    }

    static func day(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = utc
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }

    static func dayString(_ value: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let components = calendar.dateComponents([.year, .month, .day], from: value)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
}

// Fixed, deliberately isolated preview content. Never fetched or persisted by previews.
extension F1Snapshot {
    static let previewNow = F1Dates.start(date: "2026-11-05", time: "13:00:00Z")!
    static let preview: F1Snapshot = {
        let sessions: [F1Session] = [
            ("fp1", "Practice 1", "2026-11-06", "15:30:00Z"),
            ("fp2", "Practice 2", "2026-11-06", "19:00:00Z"),
            ("fp3", "Practice 3", "2026-11-07", "14:30:00Z"),
            ("qualifying", "Qualifying", "2026-11-07", "18:00:00Z"),
            ("race", "Race", "2026-11-08", "17:00:00Z")
        ].map { F1Session(id: $0.0, title: $0.1, date: $0.2, start: F1Dates.start(date: $0.2, time: $0.3)) }
        let weekend = F1Race(season: 2026, round: 20, name: "Brazilian Grand Prix", circuit: "Autódromo José Carlos Pace", date: "2026-11-08", start: sessions.last!.start, sessions: sessions)
        let last = F1Race(season: 2026, round: 19, name: "Mexico City Grand Prix", circuit: "Autódromo Hermanos Rodríguez", date: "2026-11-01", start: F1Dates.start(date: "2026-11-01", time: "20:00:00Z"), sessions: [])
        return F1Snapshot(races: [weekend], latestPodium: F1Podium(race: last, drivers: [
            F1PodiumDriver(position: 1, name: "Max Verstappen", code: "VER", team: "Red Bull"),
            F1PodiumDriver(position: 2, name: "Lewis Hamilton", code: "HAM", team: "Ferrari"),
            F1PodiumDriver(position: 3, name: "Andrea Kimi Antonelli", code: "ANT", team: "Mercedes")
        ]), fetchedAt: previewNow)
    }()
}
