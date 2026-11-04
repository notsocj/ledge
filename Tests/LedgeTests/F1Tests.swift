import Foundation
import Testing
@testable import Ledge

private func f1Data(_ races: String) -> Data {
    Data("{\"MRData\":{\"RaceTable\":{\"Races\":[\(races)]}}}".utf8)
}

private func f1RaceJSON(year: Int = 2026, round: Int = 20, date: String = "2026-11-08", extra: String = "") -> String {
    """
    {"season":"\(year)","round":"\(round)","raceName":"Brazilian Grand Prix",
     "Circuit":{"circuitName":"Interlagos"},"date":"\(date)"\(extra)}
    """
}

private let f1Results = """
,"Results":[
{"position":"3","Driver":{"givenName":"Charles","familyName":"Leclerc","code":"LEC"},"Constructor":{"name":"Ferrari"}},
{"position":"1","Driver":{"givenName":"Max","familyName":"Verstappen","code":"VER"},"Constructor":{"name":"Red Bull"}},
{"position":"2","Driver":{"givenName":"Lando","familyName":"Norris","code":"NOR"},"Constructor":{"name":"McLaren"}}]
"""

@Test func f1ParsesSprintWeekendAndLocalizesAcrossMidnight() throws {
    let data = f1Data(f1RaceJSON(extra: """
    ,"time":"17:00:00Z",
    "FirstPractice":{"date":"2026-11-06","time":"15:30:00Z"},
    "SprintQualifying":{"date":"2026-11-06","time":"19:30:00Z"},
    "Sprint":{"date":"2026-11-07","time":"15:00:00Z"},
    "Qualifying":{"date":"2026-11-07","time":"18:00:00Z"}
    """))
    let race = try #require(JolpicaClient.decode(data).first?.race)
    #expect(race.sessions.map(\.id) == ["fp1", "sprint-qualifying", "sprint", "qualifying", "race"])
    let sprintQualifying = race.sessions[1]
    let manila = try #require(TimeZone(identifier: "Asia/Manila"))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = manila
    #expect(calendar.component(.day, from: try #require(sprintQualifying.start)) == 7)
    #expect(sprintQualifying.dayLabel(timeZone: manila).contains("7"))
    #expect(sprintQualifying.timeLabel(timeZone: manila) != "Time TBC")
}

@Test func f1MissingTimeNeverInventsAMidnightStartOrShiftsPublishedDay() throws {
    let race = try #require(JolpicaClient.decode(f1Data(f1RaceJSON())).first?.race)
    let snapshot = F1Snapshot(races: [race], latestPodium: nil, fetchedAt: F1Snapshot.previewNow)
    #expect(race.start == nil)
    #expect(snapshot.countdown(at: F1Snapshot.previewNow) == "Time TBC")
    #expect(snapshot.pendingRace(at: F1Dates.start(date: "2026-11-08", time: "15:00:00Z")!) == nil)
    let zone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    #expect(race.sessions[0].dayLabel(timeZone: zone).contains("8"))
    #expect(race.sessions[0].timeLabel(timeZone: zone) == "Time TBC")
}

@Test func f1PendingDoesNotClaimLiveAndStopsAfterResultsOrOneDay() throws {
    let race = try #require(F1Snapshot.preview.races.first)
    let start = try #require(race.start)
    let snapshot = F1Snapshot.preview
    #expect(snapshot.countdown(at: start.addingTimeInterval(-30)) == "1m")
    #expect(snapshot.countdown(at: start) == "Results pending")
    #expect(snapshot.weekend(at: start)?.id == race.id)
    #expect(snapshot.pendingRace(at: start.addingTimeInterval(24 * 3600)) == nil)
    let complete = F1Snapshot(races: [race], latestPodium: F1Podium(race: race, drivers: []), fetchedAt: start)
    #expect(complete.pendingRace(at: start) == nil)
}

@Test func f1PodiumIsSortedAndPartialResultsAreNotPresentedAsComplete() throws {
    let complete = try #require(JolpicaClient.decode(f1Data(f1RaceJSON(extra: f1Results))).first?.podium)
    #expect(complete.drivers.map(\.position) == [1, 2, 3])
    #expect(complete.drivers[0].name == "Max Verstappen")
    #expect(complete.drivers[0].team == "Red Bull")
    let partial = f1RaceJSON(extra: ",\"Results\":[{\"position\":\"1\",\"Driver\":{\"givenName\":\"Max\",\"familyName\":\"Verstappen\"}}]")
    #expect(try JolpicaClient.decode(f1Data(partial)).first?.podium == nil)
}

private actor F1StubTransport {
    let responses: [String: Data]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [String: Data]) { self.responses = responses }
    func data(_ request: URLRequest) throws -> Data {
        requests.append(request)
        guard let value = responses[request.url!.path] else { throw URLError(.badURL) }
        return value
    }
}

@Test func f1ClientUsesLatestPublishedRoundInsteadOfUnpublishedLastRace() async throws {
    let previous = f1RaceJSON(round: 19, date: "2026-11-01", extra: f1Results)
    let stub = F1StubTransport([
        "/ergast/f1/2026.json": f1Data(f1RaceJSON(extra: ",\"time\":\"17:00:00Z\"")),
        "/ergast/f1/2026/results/1.json": f1Data(previous),
        "/ergast/f1/2026/19/results.json": f1Data(previous)
    ])
    let client = JolpicaClient(requestSpacing: 0, transport: { try await stub.data($0) })
    let value = try await client.fetch(at: F1Snapshot.previewNow)
    #expect(value.latestPodium?.race.round == 19)
    #expect(value.weekend(at: F1Snapshot.previewNow)?.round == 20)
    let requests = await stub.requests
    #expect(requests.count == 3)
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Ledge/") == true })
    #expect(requests.last?.url?.query == "limit=3")
}

@Test func f1ClientHandlesOffSeasonAndPreviousSeasonPodium() async throws {
    let future = f1RaceJSON(year: 2027, round: 1, date: "2027-03-07")
    let previous = f1RaceJSON(year: 2025, round: 24, date: "2025-12-07", extra: f1Results)
    let stub = F1StubTransport([
        "/ergast/f1/2026.json": f1Data(""),
        "/ergast/f1/2027.json": f1Data(future),
        "/ergast/f1/2026/results/1.json": f1Data(""),
        "/ergast/f1/2025/results/1.json": f1Data(previous),
        "/ergast/f1/2025/24/results.json": f1Data(previous)
    ])
    let client = JolpicaClient(requestSpacing: 0, transport: { try await stub.data($0) })
    let value = try await client.fetch(at: F1Snapshot.previewNow)
    #expect(value.weekend(at: F1Snapshot.previewNow)?.season == 2027)
    #expect(value.latestPodium?.race.season == 2025)
}

private actor F1LoadCounter {
    private(set) var calls = 0
    func fail(_ date: Date) throws -> F1Snapshot { calls += 1; throw URLError(.notConnectedToInternet) }
}

@MainActor @Test func f1DisabledServiceDoesNotFetchAndFailurePreservesSavedContent() async throws {
    let counter = F1LoadCounter()
    let service = F1Companion(snapshot: .preview, now: F1Snapshot.previewNow, cacheURL: nil,
                              load: { try await counter.fail($0) })
    await service.update(at: F1Snapshot.previewNow.addingTimeInterval(3600))
    #expect(await counter.calls == 0)
    #expect(service.isRunning == false)
    service.start()
    // The explicit tick uses an old fixture plus a deterministic future time, making a refresh due.
    for _ in 0..<20 where service.isRefreshing { await Task.yield() }
    await service.update(at: F1Snapshot.previewNow.addingTimeInterval(3600))
    for _ in 0..<100 where service.isRefreshing { await Task.yield() }
    #expect(service.latestPodium == F1Snapshot.preview.latestPodium)
    #expect(service.hasConnectionIssue)
    #expect(service.statusText.hasPrefix("Saved · "))
    service.stop()
    let before = await counter.calls
    await service.update(at: Date.now.addingTimeInterval(7200))
    #expect(await counter.calls == before)
    #expect(!service.isRefreshing)
}

private actor F1DelayedLoader {
    private(set) var calls = 0
    private var first: CheckedContinuation<F1Snapshot, Error>?
    func fetch(_ date: Date) async throws -> F1Snapshot {
        calls += 1
        if calls == 1 { return try await withCheckedThrowingContinuation { first = $0 } }
        return F1Snapshot(races: F1Snapshot.preview.races, latestPodium: F1Snapshot.preview.latestPodium, fetchedAt: date)
    }
    func releaseCanceledRequest() {
        first?.resume(returning: F1Snapshot(races: [], latestPodium: nil, fetchedAt: .distantPast))
        first = nil
    }
}

@MainActor @Test func f1ReenablingAfterCanceledFirstFetchRetriesAndRejectsItsLateResult() async throws {
    let loader = F1DelayedLoader()
    let service = F1Companion(cacheURL: nil, load: { try await loader.fetch($0) })
    service.start()
    for _ in 0..<100 {
        if await loader.calls == 1 { break }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(await loader.calls == 1)
    service.stop()
    service.start()
    for _ in 0..<100 {
        if await loader.calls == 2 && !service.isRefreshing { break }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(await loader.calls == 2)
    #expect(service.latestPodium == F1Snapshot.preview.latestPodium)
    await loader.releaseCanceledRequest()
    await Task.yield()
    #expect(service.latestPodium == F1Snapshot.preview.latestPodium)
    service.stop()
}

@MainActor @Test func f1CountdownTicksDoNotCauseFrequentRequests() async {
    let fresh = F1Snapshot(races: F1Snapshot.preview.races, latestPodium: F1Snapshot.preview.latestPodium, fetchedAt: .now)
    let counter = F1LoadCounter()
    let service = F1Companion(snapshot: fresh, cacheURL: nil, load: { try await counter.fail($0) })
    service.start()
    await service.update(at: fresh.fetchedAt.addingTimeInterval(60))
    await service.update(at: fresh.fetchedAt.addingTimeInterval(120))
    #expect(await counter.calls == 0)
    service.stop()
}
