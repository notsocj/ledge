import Foundation
import Observation

/// The tighter of a tool's usage windows: percent used (0–100) and when it resets.
struct Limit: Equatable {
    let percent: Double
    let resetsAt: Date?
}

enum UsageReading: Equatable {
    case loading
    case limit(Limit)
    case unavailable(String)
}

/// Claude and Codex plan limits, refreshed when the island opens (at most once a minute).
@Observable @MainActor
final class Usage {
    private(set) var claude: UsageReading = .loading
    private(set) var codex: UsageReading = .loading
    @ObservationIgnored private var lastRefresh = Date.distantPast

    // A tool counts as installed once it has made its home folder; meters only show for installed tools.
    // shortcut: checked once at launch, so installing one later needs a Ledge relaunch.
    let showsClaude = Usage.homeFolderExists(".claude")
    let showsCodex = Usage.homeFolderExists(".codex")
    var showsAny: Bool { showsClaude || showsCodex }

    func refresh() {
        guard Snapshots.folder == nil, Date.now.timeIntervalSince(lastRefresh) > 60 else { return } // renders use demo limits
        lastRefresh = .now
        if showsCodex { Task { codex = await Task.detached { CodexLimits.read() }.value } }
        if showsClaude { Task { claude = await ClaudeLimits.fetch() } }
    }

    /// Made-up limits for snapshot renders, so published images never show someone's real usage.
    func showDemo(claude: Limit, codex: Limit) {
        self.claude = .limit(claude)
        self.codex = .limit(codex)
    }

    private static func homeFolderExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.appending(path: name).path)
    }
}

/// Codex CLI logs its rate limits in every `token_count` event of its session files.
enum CodexLimits {
    static func read(sessions: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/sessions")) -> UsageReading {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: keys)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" } ?? []
        let newest = files.max { modified($0) < modified($1) }
        guard let newest, let handle = try? FileHandle(forReadingFrom: newest) else {
            return .unavailable("No Codex sessions yet")
        }
        defer { try? handle.close() }
        // The latest event is near the end; reading the tail keeps this cheap on long sessions.
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 512_000 ? size - 512_000 : 0)
        let tail = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
        return parse(log: tail) ?? .unavailable("No Codex limits logged yet")
    }

    static func parse(log: String, now: Date = .now) -> UsageReading? {
        for line in log.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let limits = (event["payload"] as? [String: Any])?["rate_limits"] as? [String: Any] else { continue }
            let windows = ["primary", "secondary"].compactMap { limits[$0] as? [String: Any] }.map { window in
                let resetsAt = (window["resets_at"] as? Double).map(Date.init(timeIntervalSince1970:))
                // A window that already reset has nothing used, whatever the old log says.
                let used = resetsAt.map { $0 < now } == true ? 0 : window["used_percent"] as? Double ?? 0
                return Limit(percent: used, resetsAt: resetsAt)
            }
            if let tightest = windows.max(by: { $0.percent < $1.percent }) { return .limit(tightest) }
        }
        return nil
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

/// Claude plan limits from the endpoint Claude Code's `/usage` uses, signed in with Claude Code's
/// saved login. Read-only: the login is never refreshed or written here, so Claude Code's own
/// sign-in can't be disturbed.
// shortcut: undocumented endpoint, so its shape may change; parse() degrades to "unavailable".
enum ClaudeLimits {
    static func fetch() async -> UsageReading {
        guard let login = await Task.detached(operation: savedLogin).value else {
            return .unavailable("Sign in to Claude Code")
        }
        if let expiresAt = login.expiresAt, expiresAt < .now {
            return .unavailable("Run claude in Terminal to refresh")
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(login.token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else {
            return .unavailable("Couldn't reach Anthropic")
        }
        if status == 401 { return .unavailable("Run claude in Terminal to refresh") }
        return status == 200 ? parse(data) : .unavailable("Claude limits unavailable (\(status))")
    }

    static func parse(_ data: Data) -> UsageReading {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unavailable("Claude limits unavailable")
        }
        let windows = ["five_hour", "seven_day"].compactMap { body[$0] as? [String: Any] }.compactMap { window -> Limit? in
            guard let used = window["utilization"] as? Double else { return nil }
            return Limit(percent: used, resetsAt: (window["resets_at"] as? String).flatMap(date))
        }
        return windows.max(by: { $0.percent < $1.percent }).map(UsageReading.limit) ?? .unavailable("Claude limits unavailable")
    }

    /// Claude Code keeps its login in the Keychain and reads it with /usr/bin/security; doing the
    /// same avoids a Keychain prompt. Never logged.
    private static func savedLogin() -> (token: String, expiresAt: Date?)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let saved = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
              let login = saved["claudeAiOauth"] as? [String: Any],
              let token = login["accessToken"] as? String else { return nil }
        return (token, (login["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) })
    }

    /// ISO 8601 with any number of fractional digits (the API sends microseconds).
    private static func date(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression))
    }
}
