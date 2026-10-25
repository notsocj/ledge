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
    // Union of tools, each ranked by whichever persona cares most; ties go to the creator's order
    // (timer before clipboard, shelf before notes).
    #expect(layout.tools.isSuperset(of: [.media, .timer, .stats, .clipboard, .windowSnapping]))
    #expect(layout.tabOrder == [.home, .media, .stats, .timer, .clipboard, .shelf, .notes])
    #expect(layout.tabOrder.count <= Layout.maxTabs)
    #expect(layout.homeWidgets == [.media, .week])
    #expect(layout.closedOrder == [.media, .timer]) // the creator picked first
    #expect(layout.chips.first == .timer && layout.chips.contains(.claude))
}
