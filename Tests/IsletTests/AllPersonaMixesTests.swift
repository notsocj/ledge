import CoreGraphics
import Testing
@testable import Islet

/// Every non-empty mix of personas, each with every member as the first pick (192 layouts).
private let mixes: [[Persona]] = {
    let all = Persona.allCases
    var result: [[Persona]] = []
    for mask in 1..<(1 << all.count) {
        let members = all.indices.filter { mask & (1 << $0) != 0 }.map { all[$0] }
        for first in members { result.append([first] + members.filter { $0 != first }) }
    }
    return result
}()

@Test func everyMixKeepsTheIslandsRules() {
    #expect(mixes.count == 192)
    for personas in mixes {
        let layout = Layout.merging(personas)
        let label = personas.map(\.rawValue).joined(separator: "+")
        #expect(layout.tabOrder.first == .home, "\(label): Home leads")
        #expect(layout.tabOrder.count <= Layout.maxTabs, "\(label): at most \(Layout.maxTabs) tabs fit beside the notch")
        #expect(Set(layout.tabOrder).count == layout.tabOrder.count, "\(label): no tab twice")
        #expect(layout.tabOrder.allSatisfy { Tool.tabs.contains($0) && layout.tools.contains($0) }, "\(label): tabs are switched-on tab tools")
        #expect(layout.tools.isSuperset(of: Persona.basics), "\(label): everyone gets the basics")
        #expect(layout.tools == Set(Persona.basics + personas.flatMap(\.ranking)), "\(label): exactly the tools its personas want")
        #expect(!layout.homeWidgets.isEmpty && Set(layout.homeWidgets.map { "\($0)" }).count == layout.homeWidgets.count, "\(label): Home has widgets, none twice")
        #expect(Set(layout.chips.map { "\($0)" }).count == layout.chips.count, "\(label): no status chip twice")
        #expect(layout.closedOrder == personas[0].closedOrder, "\(label): the first pick decides the closed notch")
    }
}

@Test func theToolsAPersonaRanksFirstAlwaysGetATab() {
    // However personas are mixed, each one's top tab survives the cut to seven.
    for personas in mixes {
        let layout = Layout.merging(personas)
        for persona in personas {
            guard let top = persona.ranking.first(where: Tool.tabs.contains) else { continue }
            #expect(layout.tabOrder.contains(top), "\(personas.map(\.rawValue)): \(persona.rawValue)'s \(top.rawValue) tab")
        }
    }
}

@Test func mixingIsOrderIndependentExceptForTheLead() {
    // Picking the same personas in a different order (same first pick) gives the same island.
    let layout = Layout.merging([.developer, .designer, .student])
    #expect(layout == Layout.merging([.developer, .student, .designer]))
}

@Test func everyToolBelongsToSomePersona() {
    // A tool no persona wants would only ever be reachable by hand in Settings.
    let wanted = Set(Persona.basics + Persona.allCases.flatMap(\.ranking))
    let orphans = Tool.allCases.filter { !wanted.contains($0) }
    #expect(orphans.isEmpty, "unranked: \(orphans.map(\.rawValue))")
}

@MainActor @Test func setupFitsTheIsland() {
    // The tools step lays chips out five across; with the heading, subtitle and buttons it must fit under
    // the island's height cap. 28pt chips with 6pt gaps; 91pt for the heading, subtitle and buttons,
    // measured from a snapshot (5 rows came to 309pt). Adding tools past 25 needs a sixth row.
    let chips = Tool.allCases.count - 1 // Home isn't offered; it's always on
    let rows = (chips + 4) / 5
    let height = 32 + 8 + 91 + CGFloat(rows) * 28 + CGFloat(rows - 1) * 6 + 14
    #expect(height <= NotchModel.maxHeight, "\(rows) rows of tools need \(height)pt")
}
