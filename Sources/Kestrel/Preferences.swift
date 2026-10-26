import ApplicationServices
import ServiceManagement
import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    // In the open island.
    case home, media, shelf, colorPicker, clipboard, calendar, timer, notes, stats, ports
    // Work everywhere, outside the island.
    case keepAwake, screenshot, volumeHUD, alerts, windowSnapping, menuBarHider, meetingAlerts, worldClock, micMute
    case audioOutput, agentAlerts, inUse

    /// Tabs, split around the notch: the first `leftTabCount` sit left of it, the rest right.
    static let tabs: [Tool] = [.home, .media, .shelf, .colorPicker, .clipboard, .timer, .notes, .stats, .ports]
    static let leftTabCount = 4
    /// Calendar has no tab of its own; it lives on Home.
    static let island: [Tool] = [.home, .media, .calendar, .shelf, .colorPicker, .clipboard, .timer, .notes, .stats, .ports]
    static let everywhere = allCases.filter { !island.contains($0) }

    var id: String { rawValue }

    /// The label on the selected tab pill.
    var shortTitle: String {
        switch self {
        case .media: "Music"
        case .clipboard: "Clips"
        case .stats: "Stats"
        case .shelf: "Shelf"
        case .volumeHUD: "Volume"
        case .alerts: "Alerts"
        case .windowSnapping: "Snapping"
        case .menuBarHider: "Menu bar"
        case .screenshot: "Capture"
        case .keepAwake: "Awake"
        case .colorPicker: "Colors"
        case .meetingAlerts: "Meetings"
        case .worldClock: "Clocks"
        case .ports: "Ports"
        case .audioOutput: "Output"
        case .agentAlerts: "Agents"
        case .inUse: "In use"
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
        case .colorPicker: "Color picker"
        case .meetingAlerts: "Meeting countdown"
        case .worldClock: "World clock"
        case .micMute: "Mic mute"
        case .ports: "Localhost ports"
        case .audioOutput: "Audio output"
        case .agentAlerts: "Agent alerts"
        case .inUse: "Mic and camera in use"
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
        case .colorPicker: "pipette-linear"
        case .meetingAlerts: "calendar-mark-linear"
        case .worldClock: "earth-linear"
        case .micMute: "microphone-linear"
        case .ports: "server-square-linear"
        case .audioOutput: "speaker-minimalistic-linear"
        case .agentAlerts: "bell-ring-linear"
        case .inUse: "record-circle-linear"
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
        case .menuBarHider: "Adds Choose Menu Bar Icons… to Kestrel's menu, which opens macOS's settings for which apps show icons."
        case .colorPicker: "⌃⌥P, or the pipette on Home: pick any color on screen. It's copied as hex and kept in the Colors tab."
        case .meetingAlerts: "A heads-up beside the notch two minutes before each meeting. Uses your calendar."
        case .worldClock: "Up to three cities' times in Home's status row. Choose them below."
        case .micMute: "⌃⌥M, or the mic button on Home: mutes your input in every app, with a red mark in the notch."
        case .ports: "What's listening on localhost, like your dev servers, with Open and Stop."
        case .audioOutput: "Switch between speakers, AirPods and other outputs from Home."
        case .agentAlerts: "The notch lights up when Claude Code or Codex finishes or needs you. Connect them below."
        case .inUse: "Shows beside the notch while any app is using your microphone or camera."
        }
    }

    var needsAccessibility: Bool { self == .volumeHUD || self == .windowSnapping }
}

extension Notification.Name {
    /// Runs setup again inside the island, from Settings or the menu bar.
    static let startOnboarding = Notification.Name("KestrelStartOnboarding")
}

/// Which tools are on. Stores the switched-off ones, so tools added in updates start switched on.
@Observable @MainActor
final class Preferences {
    static let shared = Preferences()

    private(set) var disabled: Set<Tool>
    /// In the order they were picked; the first one leads (see `Layout.merging`). Empty until chosen.
    private(set) var personas: [Persona]
    /// Whether first-run setup has been finished or skipped.
    var onboarded: Bool { didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded") } }
    @ObservationIgnored var onChange: ((Tool, Bool) -> Void)?

    private init() {
        disabled = Set((UserDefaults.standard.stringArray(forKey: "disabledTools") ?? []).compactMap(Tool.init))
        personas = (UserDefaults.standard.stringArray(forKey: "personas") ?? []).compactMap(Persona.init)
        onboarded = UserDefaults.standard.bool(forKey: "onboarded")
        adoptNewTools()
    }

    /// A layout to show without saving anything (the snapshot renderer). Overrides personas and switches.
    var preview: [Persona]?

    var layout: Layout { Layout.merging(preview ?? personas) }

    /// Tools that arrived in an update start on only if your personas want them; tools you've
    /// already seen keep whatever you set.
    private func adoptNewTools() {
        let defaults = UserDefaults.standard
        // Before this was tracked, every tool except these four already existed.
        let known = defaults.stringArray(forKey: "knownTools").map { Set($0.compactMap(Tool.init)) }
            ?? Set(Tool.allCases).subtracting([.colorPicker, .meetingAlerts, .worldClock, .micMute, .ports, .audioOutput, .agentAlerts, .inUse])
        let arrived = Tool.allCases.filter { !known.contains($0) }
        if !personas.isEmpty {
            let wanted = layout.tools
            for tool in arrived where !wanted.contains(tool) { disabled.insert(tool) }
            defaults.set(disabled.map(\.rawValue), forKey: "disabledTools")
        }
        defaults.set(Tool.allCases.map(\.rawValue), forKey: "knownTools")
    }

    /// Picking what you do rebuilds which tools are on; individual switches still work afterwards.
    func choose(_ personas: [Persona]) {
        self.personas = personas
        UserDefaults.standard.set(personas.map(\.rawValue), forKey: "personas")
        guard !personas.isEmpty else { return }
        let wanted = layout.tools
        for tool in Tool.allCases where isOn(tool) != wanted.contains(tool) {
            set(tool, on: wanted.contains(tool))
        }
    }

    func isOn(_ tool: Tool) -> Bool {
        if let preview { return Layout.merging(preview).tools.contains(tool) }
        return !disabled.contains(tool)
    }

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
            LicenseSettings(license: .shared)
            Section {
                ForEach(Persona.allCases) { persona in
                    Toggle(isOn: Binding(get: { preferences.personas.contains(persona) }, set: { on in
                        var chosen = preferences.personas.filter { $0 != persona }
                        if on { chosen.append(persona) }
                        preferences.choose(chosen)
                    })) {
                        Label {
                            Text(persona.title)
                            Text(persona.blurb)
                        } icon: {
                            Icon(name: persona.symbol)
                        }
                    }
                }
                Button("Set up again in the island") { NotificationCenter.default.post(name: .startOnboarding, object: nil) }
            } header: {
                Text("What do you do?")
            } footer: {
                Text("Pick one or more. Kestrel switches on the tools that fit and puts the ones you'll use most closest to hand. You can still change any tool below.")
                    .foregroundStyle(.secondary)
            }
            Section("In the island") {
                ForEach(Tool.island) { toggle($0) }
            }
            Section("Everywhere") {
                ForEach(Tool.everywhere) { toggle($0) }
            }
            if preferences.isOn(.agentAlerts) {
                AgentSettings(agents: .shared)
            }
            if preferences.isOn(.worldClock) {
                WorldClockSettings(clock: .shared)
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

private struct WorldClockSettings: View {
    let clock: WorldClock
    private static let zones = TimeZone.knownTimeZoneIdentifiers.sorted { WorldClock.city($0) < WorldClock.city($1) }

    var body: some View {
        Section("World clock") {
            ForEach(0..<WorldClock.limit, id: \.self) { index in
                Picker("City \(index + 1)", selection: Binding(
                    get: { index < clock.zones.count ? clock.zones[index] : "" },
                    set: { zone in
                        var zones = clock.zones
                        if index < zones.count { zones[index] = zone } else { zones.append(zone) }
                        clock.zones = zones.filter { !$0.isEmpty }
                    })) {
                    Text("None").tag("")
                    ForEach(Self.zones, id: \.self) { Text(WorldClock.city($0)).tag($0) }
                }
            }
        }
    }
}

/// Connecting edits each agent's own settings file, so it asks first and says exactly what changes.
private struct AgentSettings: View {
    let agents: AgentAlerts
    @State private var confirming: AgentAlerts.Agent?

    var body: some View {
        Section {
            row(.claude, name: "Claude Code", logo: "claude-logo", status: agents.claude)
            row(.codex, name: "Codex", logo: "codex-logo", status: agents.codex)
            if let error = agents.lastError {
                Text(error).foregroundStyle(.red)
            }
        } header: {
            Text("Coding agents")
        } footer: {
            Text("Kestrel adds a small command to each agent's settings, saving a backup of the file first. Disconnect removes it again.")
                .foregroundStyle(.secondary)
        }
        .onAppear { agents.refresh() }
        .confirmationDialog(confirming == .claude ? "Connect Claude Code?" : "Connect Codex?",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Connect") {
                if let agent = confirming { agents.connect(agent) }
                confirming = nil
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text(confirming == .claude
                 ? "Kestrel will add a Stop and a Notification hook to ~/.claude/settings.json. A backup is saved as settings.json.kestrel-backup."
                 : "Kestrel will set notify in ~/.codex/config.toml. If you already have one, it keeps running after Kestrel's. A backup is saved as config.toml.kestrel-backup.")
        }
    }

    @ViewBuilder private func row(_ agent: AgentAlerts.Agent, name: String, logo: String, status: AgentAlerts.Status) -> some View {
        LabeledContent {
            switch status {
            case .notInstalled: Text("Not installed").foregroundStyle(.secondary)
            case .connected: Button("Disconnect") { agents.disconnect(agent) }
            case .disconnected: Button("Connect…") { confirming = agent }
            case .blocked(let reason): Text(reason).foregroundStyle(.secondary)
            }
        } label: {
            Label {
                Text(name)
                Text(status == .connected ? "Connected" : status == .notInstalled ? "" : "Not connected")
            } icon: {
                Icon(name: logo)
            }
        }
    }
}
