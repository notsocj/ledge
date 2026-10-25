import AppKit
import EventKit
import Testing
@testable import Islet

@MainActor @Test func focusRollsIntoABreakThenWaitsForTheNextSession() {
    let countdown = Countdown()
    var finishes: [Countdown.Finish] = []
    countdown.onFinish = { finishes.append($0) }

    countdown.startFocus()
    #expect(countdown.focus == Countdown.Focus(onBreak: false, completed: 0) && countdown.total == 25 * 60)
    countdown.finished() // focus done: the break starts by itself
    #expect(countdown.focus == Countdown.Focus(onBreak: true, completed: 1) && countdown.isRunning && countdown.total == 5 * 60)
    countdown.finished() // break over: stops and waits
    #expect(countdown.focus == Countdown.Focus(onBreak: false, completed: 1) && !countdown.isActive)
    #expect(finishes == [.focusDone, .breakOver])

    countdown.start(minutes: 1) // a plain timer leaves focus mode
    #expect(countdown.focus == nil)
    countdown.cancel()
}

@MainActor @Test func colorsRoundTripAndFormat() {
    let hex = ColorPicker.hex(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))
    #expect(hex == "#FF8000")
    #expect(ColorPicker.color(hex: hex).map(ColorPicker.hex) == "#FF8000")
    #expect(ColorPicker.color(hex: "FF8000") == nil) // needs the #
    #expect(ColorPicker.formats("#FF8000").map(\.text) == ["#FF8000", "rgb(255, 128, 0)", "Color(red: 1.000, green: 0.502, blue: 0.000)"])
}

@MainActor @Test func pickedColorsDedupeAndKeepTwelve() {
    let picker = ColorPicker()
    let saved = picker.colors
    defer { picker.clear(); saved.reversed().forEach(picker.remember) } // leave the user's colors as they were
    picker.clear()
    for index in 0..<14 { picker.remember(String(format: "#0000%02X", index)) }
    picker.remember("#000005")
    #expect(picker.colors.count == ColorPicker.limit && picker.colors.first == "#000005")
    #expect(picker.colors.filter { $0 == "#000005" }.count == 1)
}

@Test func worldClockNamesCities() {
    #expect(WorldClock.city("America/Los_Angeles") == "Los Angeles")
    #expect(WorldClock.city("UTC") == "UTC")
}

@MainActor @Test func meetingHeadsUpOnlyInTheLastTwoMinutes() {
    let store = EKEventStore()
    let now = Date(timeIntervalSince1970: 10_000)
    func event(startingIn seconds: TimeInterval) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.startDate = now.addingTimeInterval(seconds)
        event.endDate = event.startDate.addingTimeInterval(1800)
        return event
    }
    let soon = event(startingIn: 90), later = event(startingIn: 600), started = event(startingIn: -30)
    #expect(MeetingAlerts.startingSoon([soon, later, started], at: now) == [soon])
}

@MainActor @Test func newToolsFollowTheirPersonas() {
    let designer = Layout.merging([.designer])
    #expect(designer.tabOrder.prefix(2) == [.home, .colorPicker])
    let professional = Layout.merging([.professional])
    #expect(professional.tools.isSuperset(of: [.meetingAlerts, .micMute, .worldClock]))
    #expect(professional.chips.first == .clocks)
    #expect(!Layout.standard.tabOrder.contains(.colorPicker) && Layout.standard.tabOrder.count <= Layout.maxTabs)
}
