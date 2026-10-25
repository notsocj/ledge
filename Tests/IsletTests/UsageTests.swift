import Foundation
import Testing
@testable import Islet

@Test func codexPicksTightestWindowAndZeroesResetOnes() {
    let now = Date(timeIntervalSince1970: 1_000)
    let log = """
    {"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":90,"window_minutes":300,"resets_at":500}}}}
    {"type":"event_msg","payload":{"type":"agent_message"}}
    {"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":70,"window_minutes":300,"resets_at":900},"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":5000}}}}
    """
    // Latest event wins; its 5-hour window already reset at 900, so the weekly 40% is the tightest.
    #expect(CodexLimits.parse(log: log, now: now) == .limit(Limit(percent: 40, resetsAt: Date(timeIntervalSince1970: 5000))))
    #expect(CodexLimits.parse(log: "{\"type\":\"session_meta\"}", now: now) == nil)
}

@Test func claudePicksTightestWindow() {
    let body = Data("""
    {"five_hour":{"utilization":12.0,"resets_at":"2026-10-25T20:00:00.123456+00:00"},"seven_day":{"utilization":55.0,"resets_at":"2026-10-30T08:00:00+00:00"},"seven_day_opus":null}
    """.utf8)
    #expect(ClaudeLimits.parse(body) == .limit(Limit(percent: 55, resetsAt: ISO8601DateFormatter().date(from: "2026-10-30T08:00:00Z"))))
    #expect(ClaudeLimits.parse(Data("{}".utf8)) == .unavailable("Claude limits unavailable"))
}
