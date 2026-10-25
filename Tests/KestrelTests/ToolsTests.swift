import Foundation
import Testing
@testable import Kestrel

@MainActor @Test func findsMeetingLinksAndIgnoresOtherURLs() {
    #expect(Agenda.meetingLink(in: "Notes: join https://us02web.zoom.us/j/123456?pwd=abc please")?.absoluteString == "https://us02web.zoom.us/j/123456?pwd=abc")
    #expect(Agenda.meetingLink(in: "Room 4 https://meet.google.com/abc-defg-hij")?.host == "meet.google.com")
    #expect(Agenda.meetingLink(in: "Agenda doc: https://docs.google.com/document/d/1") == nil)
}

@MainActor @Test func warnsOnceWhenBatteryCrossesTwentyAndTen() {
    #expect(Alerts.shouldWarn(from: 21, to: 20))
    #expect(Alerts.shouldWarn(from: 11, to: 9))
    #expect(!Alerts.shouldWarn(from: 20, to: 19)) // already warned at 20
    #expect(!Alerts.shouldWarn(from: 50, to: 49))
}

@MainActor @Test func formatsCountdowns() {
    #expect(Countdown.format(65) == "1:05")
    #expect(Countdown.format(0.2) == "0:01") // rounds up so it never shows 0:00 while running
    #expect(Countdown.format(3725) == "1:02:05")
}

@MainActor @Test func clipboardDedupesAndKeepsTheLatest30() {
    let history = ClipboardHistory()
    for index in 0..<35 { history.insert(.text("item \(index)")) }
    history.insert(.text("item 34"))
    #expect(history.entries.count == ClipboardHistory.limit)
    #expect(history.entries.first?.item == .text("item 34"))
    #expect(history.entries.filter { $0.item == .text("item 34") }.count == 1)
}
