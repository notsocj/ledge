import Testing
import CoreGraphics
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
    #expect(model.panelHeight >= model.notchSize.height + NotificationCapsule.height + NotificationCapsule.shadowSpace)
    model.expanded = true
    #expect(model.panelHeight == normal)
}

@Test func notificationMorphUsesTheRestingIslandAndKeepsCameraClearance() {
    let notch = CGSize(width: 180, height: 32)
    let wings = CGSize(width: 268, height: 32)
    let resting = NotificationGeometry(notchSize: notch, restingSize: wings, progress: 0)
    let notifying = NotificationGeometry(notchSize: notch, restingSize: wings, progress: 1)
    #expect(resting.size == wings)
    #expect(notifying.size == CGSize(width: 364, height: 96))
    #expect(NotificationGeometry.bend(at: 0) == 0)
    #expect(NotificationGeometry.bend(at: 1) == 0)
    #expect(NotificationGeometry.bend(at: 0.5) > 0)
    for progress in stride(from: CGFloat(0), through: 1, by: 0.1) {
        let size = NotificationGeometry(notchSize: notch, restingSize: wings, progress: progress).size
        #expect(size.width >= notch.width && size.height >= notch.height)
    }
}

@Test func notificationContentWaitsForTheSurfaceToFit() {
    #expect(NotificationGeometry.contentReveal(at: 0) == 0)
    #expect(NotificationGeometry.contentReveal(at: 0.8) == 0)
    #expect(NotificationGeometry.contentReveal(at: 0.95) > 0)
    #expect(NotificationGeometry.contentReveal(at: 1) == 1)
    #expect(NotificationGeometry.contentReveal(at: 1.02) == 1)
}

@MainActor @Test func replacementNotificationOutlivesThePreviousExpiry() async throws {
    let model = NotchModel()
    model.show(.battery(percent: 20, charging: false), seconds: 0)
    let replacement = Banner.agent(name: "Codex", waiting: false, project: "ledge")
    model.show(replacement, seconds: 60)
    try await Task.sleep(for: .milliseconds(30))
    #expect(model.banner == replacement)
    // A changed status replaces the existing source; exact duplicates intentionally do not renew it.
    model.show(.agent(name: "Codex", waiting: true, project: "ledge"), seconds: 0)
    try await Task.sleep(for: .milliseconds(30))
    #expect(model.banner == nil)
}
