import ApplicationServices
import ServiceManagement
import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    // In the open island.
    case home, media, shelf, clipboard, calendar, timer, notes, stats
    // Work everywhere, outside the island.
    case keepAwake, screenshot, volumeHUD, alerts, windowSnapping, menuBarHider

    /// Tabs, split around the notch: the first `leftTabCount` sit left of it, the rest right.
    static let tabs: [Tool] = [.home, .media, .shelf, .clipboard, .timer, .notes, .stats]
    static let leftTabCount = 4
    /// Calendar has no tab of its own; it lives on Home.
    static let island: [Tool] = [.home, .media, .calendar, .shelf, .clipboard, .timer, .notes, .stats]
    static let everywhere = allCases.filter { !island.contains($0) }

    var id: String { rawValue }

    /// The label on the selected tab pill.
    var shortTitle: String {
        switch self {
        case .media: "Music"
        case .clipboard: "Clips"
        case .stats: "Stats"
        default: title
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .media: "Now playing"
        case .shelf: "File shelf"
        case .clipboard: "Clipboard history"
        case .calendar: "Calendar"
        case .timer: "Timer"
        case .notes: "Notes"
        case .stats: "System stats"
        case .keepAwake: "Keep awake"
        case .screenshot: "Screenshots"
        case .volumeHUD: "Volume and brightness"
        case .alerts: "AirPods and battery alerts"
        case .windowSnapping: "Window snapping"
        case .menuBarHider: "Menu bar icons"
        }
    }

    var symbol: String {
        switch self {
        case .home: "home-2-linear"
        case .media: "music-note-linear"
        case .shelf: "inbox-linear"
        case .clipboard: "copy-linear"
        case .calendar: "calendar-linear"
        case .timer: "stopwatch-linear"
        case .notes: "notes-linear"
        case .stats: "chart-2-linear"
        case .keepAwake: "cup-hot-linear"
        case .screenshot: "camera-linear"
        case .volumeHUD: "volume-loud-linear"
        case .alerts: "headphones-round-linear"
        case .windowSnapping: "window-frame-linear"
        case .menuBarHider: "hamburger-menu-linear"
        }
    }

    var detail: String {
        switch self {
        case .home: "Now playing, your week, quick actions, and a status row for every tool."
        case .media: "Song, controls and synced lyrics."
        case .shelf: "Drag files onto the notch to keep them; drag them out when you need them."
        case .clipboard: "The last 30 things you copied. Kept in memory only; passwords from password managers are skipped."
        case .calendar: "A week strip on Home; click a day for its events, with Join for Zoom, Meet, Teams and Webex."
        case .timer: "Countdown timers that tick in the notch."
        case .notes: "A scratchpad that saves as you type."
        case .stats: "CPU, memory, network, battery, and Claude and Codex usage limits."
        case .keepAwake: "Stops your Mac from sleeping, from the cup button on Home."
        case .screenshot: "⌃⌥S, or the camera button. Saved to Pictures, copied, and put on the shelf."
        case .volumeHUD: "Shows volume and brightness changes in the notch. Needs Accessibility."
        case .alerts: "Battery when you plug in or run low, and headphone battery when they connect."
        case .windowSnapping: "Drag a window to a screen edge, or ⌃⌥ + arrow keys or Return. Needs Accessibility."
        case .menuBarHider: "A button on Home that opens macOS's Menu Bar settings, where you choose which apps show icons."
        }
    }

    var needsAccessibility: Bool { self == .volumeHUD || self == .windowSnapping }
}

/// Which tools are on. Stores the switched-off ones, so tools added in updates start switched on.
@Observable @MainActor
final class Preferences {
    static let shared = Preferences()

    private(set) var disabled: Set<Tool>
    @ObservationIgnored var onChange: ((Tool, Bool) -> Void)?

    private init() {
        disabled = Set((UserDefaults.standard.stringArray(forKey: "disabledTools") ?? []).compactMap(Tool.init))
    }

    func isOn(_ tool: Tool) -> Bool { !disabled.contains(tool) }

    func set(_ tool: Tool, on: Bool) {
        if on { disabled.remove(tool) } else { disabled.insert(tool) }
        UserDefaults.standard.set(disabled.map(\.rawValue), forKey: "disabledTools")
        onChange?(tool, on)
    }
}

struct SettingsView: View {
    let preferences: Preferences
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        Form {
            Section("In the island") {
                ForEach(Tool.island) { toggle($0) }
            }
            Section("Everywhere") {
                ForEach(Tool.everywhere) { toggle($0) }
            }
            Section("General") {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                LabeledContent("Accessibility") {
                    if trusted {
                        Text("Allowed").foregroundStyle(.secondary)
                    } else {
                        Button("Allow in System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            }
            Section("Credits") {
                // Required by the icons' CC BY 4.0 license.
                Link("Icons: Solar by 480 Design, CC BY 4.0", destination: URL(string: "https://www.figma.com/community/file/1166831539721848736")!)
                Link("Now playing: mediaremote-adapter by Jonas van den Berg, BSD 3-Clause", destination: URL(string: "https://github.com/ungive/mediaremote-adapter")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .onAppear { NSApp.activate() } // an accessory app's windows otherwise open behind others
        .task {
            while !trusted, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                trusted = AXIsProcessTrusted()
            }
        }
    }

    private func toggle(_ tool: Tool) -> some View {
        Toggle(isOn: Binding(get: { preferences.isOn(tool) }, set: { preferences.set(tool, on: $0) })) {
            Label {
                Text(tool.title)
                Text(tool.detail)
            } icon: {
                Icon(name: tool.symbol)
            }
        }
    }
}
