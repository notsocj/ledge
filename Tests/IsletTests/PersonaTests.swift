import Testing
@testable import Islet

@Test func noPersonaKeepsEverythingAsBefore() {
    #expect(Layout.merging([]) == .standard)
}

@Test func onePersonaOrdersTabsByItsRanking() {
    let layout = Layout.merging([.student])
    #expect(layout.tabOrder == [.home, .timer, .notes, .media, .clipboard]) // calendar lives on Home, not a tab
    #expect(layout.tools.contains(.volumeHUD) && layout.tools.contains(.alerts)) // basics for everyone
    #expect(!layout.tools.contains(.windowSnapping))
    #expect(layout.homeWidgets == [.week, .media])
    #expect(layout.closedOrder == [.timer, .media])
}

@Test func mergedPersonasTakeEachToolsBestRankAndTheFirstPicksHome() {
    let layout = Layout.merging([.creator, .developer])
    // Union of tools, each ranked by whichever persona cares most; ties go to the creator's order.
    // Tabs rank among each persona's tabs; eight qualify, so the lowest (notes) doesn't get one.
    #expect(layout.tools.isSuperset(of: [.media, .timer, .stats, .clipboard, .windowSnapping]))
    #expect(layout.tabOrder == [.home, .media, .stats, .timer, .ports, .shelf, .clipboard])
    #expect(layout.tabOrder.count <= Layout.maxTabs)
    #expect(layout.homeWidgets == [.media, .week])
    #expect(layout.closedOrder == [.media, .timer]) // the creator picked first
    #expect(layout.chips.first == .timer && layout.chips.contains(.claude))
}

@MainActor @Test func onboardingPicksRecommendToolsAndTheToolsStepCanAdjust() {
    let flow = Onboarding()
    flow.toggle(.student)
    #expect(flow.tools == Layout.merging([.student]).tools)
    flow.toggle(.windowSnapping)          // add one the persona didn't suggest
    #expect(flow.tools.contains(.windowSnapping))
    flow.toggle(.developer)               // a new persona pick re-recommends for the combination
    #expect(flow.personas == [.student, .developer] && flow.tools == Layout.merging([.student, .developer]).tools)
    flow.toggle(.student)
    flow.toggle(.developer)
    #expect(flow.tools.isEmpty)           // nothing picked, nothing to continue with
}
