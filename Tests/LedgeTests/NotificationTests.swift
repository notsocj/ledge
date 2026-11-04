import Testing
@testable import Ledge

@Test func notificationsKeepContextReadableAndStatusExplicit() {
    let done = Banner.agent(name: "Codex", waiting: false, project: " / ").notificationContent()
    #expect(done.title == "Codex" && done.detail == "Task completed" && done.status == "Done")
    let waiting = Banner.agent(name: "Claude", waiting: true, project: "  ledge  ").notificationContent()
    #expect(waiting.title == "Claude Code" && waiting.detail == "ledge" && waiting.status == "Needs you")
    #expect(waiting.accessibilityLabel == "Claude Code, ledge, Needs you")
}

@Test func notificationLevelsClampAndKeyboardFeedbackIsImmediate() {
    #expect(Banner.level(symbol: "sun-bold", value: 1.5).notificationContent().status == "100%")
    #expect(Banner.level(symbol: "volume-loud-bold", value: -.infinity).notificationContent().level == 0)
    #expect(Banner.level(symbol: "volume-loud-bold", value: 0.6).isImmediateFeedback)
    #expect(Banner.mic(muted: true).isImmediateFeedback)
    #expect(!Banner.agent(name: "Codex", waiting: false, project: "ledge").isImmediateFeedback)
}

@MainActor @Test func notificationPanelReservesSpaceAfterAShortTab() {
    let model = NotchModel()
    model.contentHeights[.home] = 20
    let normal = model.panelHeight
    model.show(.battery(percent: 54, charging: true), seconds: 0)
    #expect(model.panelHeight >= model.notchSize.height + NotificationCapsule.gap
            + NotificationCapsule.height + NotificationCapsule.shadowSpace)
    model.expanded = true
    #expect(model.panelHeight == normal)
}

@MainActor @Test func replacementNotificationOutlivesThePreviousExpiry() async throws {
    let model = NotchModel()
    model.show(.battery(percent: 20, charging: false), seconds: 0)
    let replacement = Banner.agent(name: "Codex", waiting: false, project: "ledge")
    model.show(replacement, seconds: 60)
    try await Task.sleep(for: .milliseconds(30))
    #expect(model.banner == replacement)
    model.show(replacement, seconds: 0)
    try await Task.sleep(for: .milliseconds(30))
    #expect(model.banner == nil)
}
