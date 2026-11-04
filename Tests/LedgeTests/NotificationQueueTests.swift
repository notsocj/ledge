import Foundation
import Testing
@testable import Ledge

private let notificationNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
private let agentWaiting = Banner.agent(name: "Codex", waiting: true, project: "ledge")
private let agentDone = Banner.agent(name: "Codex", waiting: false, project: "ledge")
private let charging = Banner.battery(percent: 54, charging: true)

@Test func anAmbientAlertWaitsForAnImportantOne() {
    var queue = NotificationQueue()
    #expect(queue.submit(agentWaiting, seconds: 10, at: notificationNow) == agentWaiting)
    #expect(queue.submit(charging, seconds: 3, at: notificationNow.addingTimeInterval(1)) == nil)
    #expect(queue.banner == agentWaiting)
    #expect(queue.pending.count == 1)
    #expect(queue.tick(at: notificationNow.addingTimeInterval(10)) == charging)
    #expect(queue.banner == charging)
}

@Test func newerSourceStateResolvesWaitingEvenAtLowerPriority() {
    var queue = NotificationQueue()
    queue.submit(agentWaiting, seconds: 10, at: notificationNow)
    #expect(queue.submit(agentDone, seconds: 6, at: notificationNow.addingTimeInterval(1)) == agentDone)
    #expect(queue.banner == agentDone)
    #expect(queue.pending.isEmpty)
    queue.tick(at: notificationNow.addingTimeInterval(7))
    #expect(queue.banner == nil)
}

@Test func duplicatesDoNotExtendVisibleTimeOrReplayWithinFreshness() {
    var queue = NotificationQueue()
    queue.submit(agentDone, seconds: 6, at: notificationNow)
    for second in 1..<6 {
        #expect(queue.submit(agentDone, seconds: 6, at: notificationNow.addingTimeInterval(Double(second))) == nil)
    }
    queue.tick(at: notificationNow.addingTimeInterval(6))
    #expect(queue.banner == nil)
    queue.submit(agentDone, seconds: 6, at: notificationNow.addingTimeInterval(7))
    #expect(queue.banner == nil)
    #expect(queue.submit(agentDone, seconds: 6, at: notificationNow.addingTimeInterval(20)) == agentDone)
}

@Test func queuedSourceUpdatesCoalesceWithoutChangingAnUnrelatedUrgentAlert() {
    var queue = NotificationQueue()
    queue.submit(agentWaiting, seconds: 10, at: notificationNow)
    queue.submit(charging, seconds: 3, at: notificationNow.addingTimeInterval(1))
    let unplugged = Banner.battery(percent: 53, charging: false)
    queue.submit(unplugged, seconds: 3, at: notificationNow.addingTimeInterval(2))
    #expect(queue.banner == agentWaiting)
    #expect(queue.pending.count == 1)
    #expect(queue.tick(at: notificationNow.addingTimeInterval(10)) == unplugged)
}

@Test func anUrgentAlertPreemptsAndResumesTheRemainingPresentationWithoutRepeatingSound() {
    var queue = NotificationQueue()
    queue.submit(charging, seconds: 6, at: notificationNow)
    #expect(queue.submit(agentWaiting, seconds: 4, at: notificationNow.addingTimeInterval(2)) == agentWaiting)
    #expect(queue.tick(at: notificationNow.addingTimeInterval(6)) == nil)
    #expect(queue.banner == charging)
    #expect(queue.current?.visibleUntil == notificationNow.addingTimeInterval(10))
    queue.tick(at: notificationNow.addingTimeInterval(10))
    #expect(queue.banner == nil)
}

@Test func importantAlertsSurviveImmediateFeedbackButTheFeedbackNeverQueues() {
    var queue = NotificationQueue()
    queue.submit(agentWaiting, seconds: 10, at: notificationNow)
    let first = Banner.level(symbol: "volume-loud-bold", value: 0.4)
    let second = Banner.level(symbol: "volume-loud-bold", value: 0.5)
    queue.submit(first, seconds: 2, at: notificationNow.addingTimeInterval(2))
    queue.submit(second, seconds: 2, at: notificationNow.addingTimeInterval(3))
    #expect(queue.pending.count == 1)
    #expect(queue.banner == second)
    #expect(queue.tick(at: notificationNow.addingTimeInterval(5)) == nil)
    #expect(queue.banner == agentWaiting)
    #expect(queue.current?.visibleUntil == notificationNow.addingTimeInterval(13))
}

@Test func openingTheIslandHoldsFreshAlertsAndDiscardsStaleOnes() {
    var queue = NotificationQueue()
    queue.submit(agentWaiting, seconds: 10, at: notificationNow)
    queue.setSuspended(true, at: notificationNow.addingTimeInterval(2))
    queue.submit(charging, seconds: 3, at: notificationNow.addingTimeInterval(3))
    queue.submit(.mic(muted: true), seconds: 2, at: notificationNow.addingTimeInterval(4))
    #expect(queue.banner == nil)
    #expect(queue.pending.count == 2)
    #expect(queue.setSuspended(false, at: notificationNow.addingTimeInterval(20)) == nil)
    #expect(queue.banner == agentWaiting)
    #expect(queue.pending.isEmpty)
    queue.setSuspended(true, at: notificationNow.addingTimeInterval(21))
    queue.setSuspended(false, at: notificationNow.addingTimeInterval(40))
    #expect(queue.banner == nil)
}

@Test func aQueuedMeetingExpiresSoonAfterItsStart() {
    var queue = NotificationQueue()
    queue.setSuspended(true, at: notificationNow)
    let meeting = Banner.meeting(title: "Review", startsAt: notificationNow.addingTimeInterval(-10))
    queue.submit(meeting, seconds: 8, at: notificationNow)
    #expect(queue.nextDeadline == notificationNow.addingTimeInterval(20))
    queue.setSuspended(false, at: notificationNow.addingTimeInterval(21))
    #expect(queue.banner == nil)
}

@Test func pendingCapacityEvictsTheOldestLowPriorityAndPreservesUrgentAlerts() {
    var queue = NotificationQueue()
    queue.setSuspended(true, at: notificationNow)
    queue.submit(agentWaiting, seconds: 10, at: notificationNow)
    for index in 0..<5 {
        queue.submit(.message(symbol: "source-\(index)", text: "Update \(index)"), seconds: 3, at: notificationNow)
    }
    #expect(queue.pending.count == NotificationQueue.capacity)
    #expect(queue.pending.contains { $0.banner == agentWaiting })
    #expect(!queue.pending.contains { $0.key == "message:source-0" || $0.key == "message:source-1" })
    #expect(queue.setSuspended(false, at: notificationNow.addingTimeInterval(1)) == agentWaiting)
    #expect(queue.tick(at: notificationNow.addingTimeInterval(11)) == .message(symbol: "source-2", text: "Update 2"))
}

@Test func aUserRequestedPreviewCanReplayWithoutDisablingBackgroundDeduplication() {
    var queue = NotificationQueue()
    let preview = Banner.message(symbol: "ledge-mark", text: "Notification preview")
    queue.submit(preview, seconds: 6, at: notificationNow, allowRepeat: true)
    queue.tick(at: notificationNow.addingTimeInterval(6))
    #expect(queue.submit(preview, seconds: 6, at: notificationNow.addingTimeInterval(7), allowRepeat: true) == preview)
    #expect(preview.notificationSound == "Pop")
}

@MainActor @Test func modelDefersNotificationsDuringHomeAndFileDrag() {
    let model = NotchModel()
    var deliveries: [Banner] = []
    model.onBannerPresented = { deliveries.append($0) }
    model.expanded = true
    model.show(agentWaiting, seconds: 10)
    #expect(model.banner == nil)
    #expect(deliveries.isEmpty)
    model.fileDrag = .far
    model.expanded = false
    #expect(model.banner == nil)
    model.fileDrag = nil
    #expect(model.banner == agentWaiting)
    #expect(deliveries == [agentWaiting])
}

@Test func resolvingOneAgentLetsAnotherWaitingAgentTakePriority() {
    var queue = NotificationQueue()
    let otherWaiting = Banner.agent(name: "Claude", waiting: true, project: "website")
    queue.submit(agentWaiting, seconds: 10, at: notificationNow)
    queue.submit(otherWaiting, seconds: 10, at: notificationNow.addingTimeInterval(1))
    #expect(queue.submit(agentDone, seconds: 6, at: notificationNow.addingTimeInterval(2)) == otherWaiting)
    #expect(queue.banner == otherWaiting)
    #expect(queue.tick(at: notificationNow.addingTimeInterval(12)) == agentDone)
}

@Test func disablingAToolPurgesOnlyItsAlertsAndDuplicateMemory() {
    var queue = NotificationQueue()
    queue.submit(agentWaiting, seconds: 10, at: notificationNow)
    queue.submit(charging, seconds: 3, at: notificationNow.addingTimeInterval(1))
    #expect(queue.remove(where: { $0.sourceTool == .agentAlerts }, at: notificationNow.addingTimeInterval(2)) == charging)
    #expect(queue.banner == charging)
    #expect(queue.pending.isEmpty)
    // Re-enabling the tool permits a new event with the same content.
    #expect(queue.submit(agentWaiting, seconds: 10, at: notificationNow.addingTimeInterval(3)) == agentWaiting)
    queue.setSuspended(true, at: notificationNow.addingTimeInterval(4))
    queue.remove(where: { $0.sourceTool == .agentAlerts }, at: notificationNow.addingTimeInterval(5))
    queue.setSuspended(false, at: notificationNow.addingTimeInterval(6))
    #expect(queue.banner == charging)
    #expect(Banner.message(symbol: "ledge-mark", text: "Notification preview").sourceTool == nil)
}
