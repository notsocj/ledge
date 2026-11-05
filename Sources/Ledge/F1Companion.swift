import Foundation
import Observation

/// Opt-in only: construction does not read the cache, start timers, or make requests.
@Observable @MainActor
final class F1Companion {
    private(set) var snapshot: F1Snapshot?
    private(set) var now: Date
    private(set) var isRunning = false
    private(set) var isRefreshing = false
    private(set) var hasConnectionIssue = false
    private(set) var isUsingSavedData = false

    var races: [F1Race] { snapshot?.races ?? [] }
    var latestPodium: F1Podium? { snapshot?.latestPodium }
    var lastUpdated: Date? { snapshot?.fetchedAt }
    var weekend: F1Race? { snapshot?.weekend(at: now) }
    var isResultsPending: Bool { snapshot?.pendingRace(at: now) != nil }
    var countdown: String { snapshot?.countdown(at: now) ?? (isRefreshing ? "Updating…" : "Schedule TBC") }
    var statusText: String {
        if isRefreshing { return "Updating…" }
        guard let lastUpdated else { return hasConnectionIssue ? "Couldn’t update · Retrying soon" : "Schedule unavailable" }
        let age = max(0, now.timeIntervalSince(lastUpdated))
        let stamp: String
        if age < 60 { stamp = "Updated just now" }
        else if age < 60 * 60 { stamp = "Updated \(Int(age / 60))m ago" }
        else if age < 24 * 60 * 60 { stamp = "Updated \(Int(age / 3600))h ago" }
        else { stamp = "Updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))" }
        return (hasConnectionIssue || isUsingSavedData ? "Saved · " : "") + stamp
    }

    @ObservationIgnored private let cacheURL: URL?
    @ObservationIgnored private let load: @Sendable (Date) async throws -> F1Snapshot
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var generation = 0

    init(snapshot: F1Snapshot? = nil, now: Date = .now, cacheURL: URL? = F1Companion.defaultCacheURL,
         load: @escaping @Sendable (Date) async throws -> F1Snapshot = { try await JolpicaClient().fetch(at: $0) }) {
        self.snapshot = snapshot
        self.now = now
        self.cacheURL = cacheURL
        self.load = load
    }

    /// For snapshots: fixed preview data at a fixed time. Nothing is fetched, cached or scheduled.
    func showDemo(_ snapshot: F1Snapshot, now: Date) {
        self.snapshot = snapshot
        self.now = now
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        generation += 1
        now = .now
        if snapshot == nil, let cacheURL,
           let data = try? Data(contentsOf: cacheURL), data.count < 2_000_000,
           let saved = try? JSONDecoder().decode(F1Snapshot.self, from: data),
           saved.fetchedAt <= now.addingTimeInterval(60) {
            snapshot = saved
            isUsingSavedData = true
        }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRunning else { return }
                await self.update(at: .now)
                do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                catch { return }
            }
        }
    }

    func stop() {
        isRunning = false
        generation += 1
        task?.cancel()
        task = nil
        // A canceled first request must not leave an empty feature throttled on re-enable.
        lastAttempt = nil
        isRefreshing = false
    }

    /// The clock changes locally once a minute; network checks are deliberately infrequent.
    func update(at date: Date) async {
        guard isRunning else { return }
        now = date
        let interval: TimeInterval = hasConnectionIssue || isResultsPending ? 5 * 60 : 30 * 60
        let previous = lastAttempt ?? lastUpdated
        guard !isRefreshing, previous == nil || date.timeIntervalSince(previous!) >= interval else { return }
        lastAttempt = date
        isRefreshing = true
        let token = generation
        do {
            let fresh = try await load(date)
            guard !Task.isCancelled, isRunning, generation == token else { return }
            let merged = F1Snapshot(races: fresh.races, latestPodium: fresh.latestPodium ?? snapshot?.latestPodium,
                                    fetchedAt: fresh.fetchedAt)
            snapshot = merged
            hasConnectionIssue = false
            isUsingSavedData = false
            if let cacheURL, let data = try? JSONEncoder().encode(merged) {
                try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheURL, options: .atomic)
            }
        } catch {
            guard !Task.isCancelled, isRunning, generation == token else { return }
            hasConnectionIssue = true
        }
        guard generation == token else { return }
        isRefreshing = false
    }

    nonisolated static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.ledge.Ledge", isDirectory: true).appendingPathComponent("f1-weekend.json")
    }
}
