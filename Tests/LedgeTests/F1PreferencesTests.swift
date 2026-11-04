import Foundation
import Testing
@testable import Ledge

@MainActor @Test func f1RequiresExplicitOptInAndSurvivesPersonaChanges() {
    let suite = "LedgeTests.F1.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = Preferences(defaults: defaults)
    #expect(!preferences.isOn(.f1))
    for persona in Persona.allCases {
        preferences.choose([persona])
        #expect(!preferences.isOn(.f1))
    }
    preferences.set(.f1, on: true)
    preferences.choose([.developer, .creator])
    #expect(preferences.isOn(.f1))
    #expect(Preferences(defaults: defaults).isOn(.f1))
    let tabs = NotchModel().tabs(in: preferences)
    #expect(tabs.last == .f1 && tabs.count <= Layout.maxTabs)
    preferences.set(.f1, on: false)
    #expect(!Preferences(defaults: defaults).isOn(.f1))
    #expect(!NotchModel().tabs(in: preferences).contains(.f1))
    let setup = Onboarding()
    setup.toggle(.f1)
    setup.toggle(.student)
    #expect(setup.tools.contains(.f1))
    setup.toggle(.f1)
    setup.toggle(.developer)
    #expect(!setup.tools.contains(.f1))
}

@MainActor @Test func f1IsOffWhenUpgradingAnExistingInstallation() {
    let suite = "LedgeTests.F1.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(Tool.allCases.filter { $0 != .f1 }.map(\.rawValue), forKey: "knownTools")
    defaults.set([], forKey: "disabledTools")
    let preferences = Preferences(defaults: defaults)
    #expect(!preferences.isOn(.f1))
    #expect(!Layout.standard.tools.contains(.f1))
}
