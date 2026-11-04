import Foundation

/// Small, read-only Jolpica client. Requests are paced well below the API's burst limit.
struct JolpicaClient {
    typealias Transport = @Sendable (URLRequest) async throws -> Data
    let transport: Transport
    let requestSpacing: UInt64

    init(requestSpacing: UInt64 = 300_000_000, transport: @escaping Transport = { try await JolpicaClient.download($0) }) {
        self.transport = transport
        self.requestSpacing = requestSpacing
    }

    func fetch(at now: Date) async throws -> F1Snapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = F1Dates.utc
        let year = calendar.component(.year, from: now)
        var races = try await get("\(year).json").compactMap(\.race)
        if !races.contains(where: { $0.isUpcoming(at: now) }) {
            races += try await get("\(year + 1).json").compactMap(\.race)
        }

        // A winner query finds the latest *published* race, including while the next is pending.
        var winners = try await get("\(year)/results/1.json")
        if winners.isEmpty { winners = try await get("\(year - 1)/results/1.json") }
        let latest = winners.compactMap(\.race).max {
            ($0.season, $0.round) < ($1.season, $1.round)
        }
        var podium: F1Podium?
        if let latest {
            let result = try await get("\(latest.season)/\(latest.round)/results.json", limit: 3)
            podium = result.first(where: { $0.race?.id == latest.id })?.podium
            // Do not replace a saved complete podium with a partially published result.
            guard podium != nil else { throw F1APIError.incompletePodium }
        }
        return F1Snapshot(races: races.sorted { $0.sortDate < $1.sortDate }, latestPodium: podium, fetchedAt: now)
    }

    private func get(_ path: String, limit: Int = 100) async throws -> [JolpicaRace] {
        try Task.checkCancellation()
        if requestSpacing > 0 { try await Task.sleep(nanoseconds: requestSpacing) }
        var request = URLRequest(url: URL(string: "https://api.jolpi.ca/ergast/f1/\(path)?limit=\(limit)")!)
        request.timeoutInterval = 15
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        request.setValue("Ledge/\(version) (macOS; https://keepledge.vercel.app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try Self.decode(try await transport(request))
    }

    static func decode(_ data: Data) throws -> [JolpicaRace] {
        try JSONDecoder().decode(JolpicaEnvelope.self, from: data).MRData.RaceTable.Races
    }

    static func download(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw F1APIError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard data.count < 2_000_000 else { throw F1APIError.oversizedResponse }
        return data
    }
}

enum F1APIError: Error {
    case httpStatus(Int), oversizedResponse, incompletePodium
}

private struct JolpicaEnvelope: Decodable {
    let MRData: Metadata
    struct Metadata: Decodable {
        let RaceTable: Table
        struct Table: Decodable { let Races: [JolpicaRace] }
    }
}

struct JolpicaRace: Decodable {
    let season: String
    let round: String
    let raceName: String
    let Circuit: CircuitInfo
    let date: String
    let time: String?
    let FirstPractice: Session?
    let SecondPractice: Session?
    let ThirdPractice: Session?
    let Qualifying: Session?
    let Sprint: Session?
    let SprintQualifying: Session?
    let SprintShootout: Session?
    let Results: [Result]?

    struct CircuitInfo: Decodable { let circuitName: String }
    struct Session: Decodable { let date: String; let time: String? }
    struct Result: Decodable {
        let position: String
        let Driver: DriverInfo
        let Constructor: ConstructorInfo?
        struct DriverInfo: Decodable {
            let givenName: String
            let familyName: String
            let code: String?
        }
        struct ConstructorInfo: Decodable { let name: String }
    }

    var race: F1Race? {
        guard let season = Int(season), let round = Int(round), round > 0,
              F1Dates.day(date) != nil else { return nil }
        let candidates: [(String, String, Session?)] = [
            ("fp1", "Practice 1", FirstPractice),
            ("fp2", "Practice 2", SecondPractice),
            ("fp3", "Practice 3", ThirdPractice),
            ("sprint-qualifying", "Sprint qualifying", SprintQualifying ?? SprintShootout),
            ("sprint", "Sprint", Sprint),
            ("qualifying", "Qualifying", Qualifying),
            ("race", "Race", Session(date: date, time: time))
        ]
        let sessions = candidates.compactMap { id, title, source -> F1Session? in
            guard let source, F1Dates.day(source.date) != nil else { return nil }
            return F1Session(id: id, title: title, date: source.date, start: F1Dates.start(date: source.date, time: source.time))
        }.sorted {
            ($0.start ?? F1Dates.day($0.date)!) < ($1.start ?? F1Dates.day($1.date)!)
        }
        return F1Race(season: season, round: round, name: raceName, circuit: Circuit.circuitName,
                      date: date, start: F1Dates.start(date: date, time: time), sessions: sessions)
    }

    var podium: F1Podium? {
        guard let race else { return nil }
        let drivers = (Results ?? []).compactMap { result -> F1PodiumDriver? in
            guard let position = Int(result.position), (1...3).contains(position) else { return nil }
            return F1PodiumDriver(position: position, name: "\(result.Driver.givenName) \(result.Driver.familyName)",
                                  code: result.Driver.code ?? String(result.Driver.familyName.prefix(3)).uppercased(),
                                  team: result.Constructor?.name ?? "Team unavailable")
        }.sorted { $0.position < $1.position }
        guard drivers.map(\.position) == [1, 2, 3] else { return nil }
        return F1Podium(race: race, drivers: drivers)
    }
}
