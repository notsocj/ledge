import AppKit
import EventKit
import SwiftUI

/// The first thing the island shows: what's playing, your week, quick actions, and one status row
/// for everything else. Each part opens its full tool.
struct HomeView: View {
    let app: NotchController
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The widgets share the width equally; one on its own takes all of it.
            if !widgets.isEmpty {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(Array(widgets.enumerated()), id: \.offset) { index, widget in
                        switch widget {
                        case .media: MediaWidget(nowPlaying: app.nowPlaying, wide: widgets.count == 1) { open(.media) }.entrance(index, shown)
                        case .week: WeekWidget(agenda: app.agenda).entrance(index, shown)
                        }
                    }
                }
            }
            // One bar along the bottom: what's going on at the left, things to do at the right.
            let chips = StatusRow.hasChips(app), actions = QuickActions.hasActions(app)
            if chips || actions {
                HStack(spacing: 12) {
                    if chips { StatusRow(app: app, open: open) } else { Spacer(minLength: 0) }
                    if actions { QuickActions(app: app) }
                }
                .frame(height: 28)
                .entrance(2, shown)
            }
        }
        .onAppear { shown = true }
        .task {
            await app.agenda.refreshIfAllowed()
            app.usage.refresh()
            while !Task.isCancelled {
                app.stats.sample()
                if app.preferences.isOn(.audioOutput) { app.audioOutputs.refresh() }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// In the order your personas put them, skipping switched-off tools.
    private var widgets: [HomeWidget] {
        app.preferences.layout.homeWidgets.filter { app.preferences.isOn($0 == .media ? .media : .calendar) }
    }

    private func open(_ tool: Tool) {
        withAnimation(Motion.snappy) { app.open(tool) }
    }
}

/// Home's parts settle in one after another as the island opens. The island opens dozens of times a
/// day, so the reveal is short and small enough never to feel like waiting.
private struct Entrance: ViewModifier {
    let index: Int
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 4)
            .animation(Motion.easeOut(0.22).delay(Double(index) * 0.04), value: shown)
    }
}

private extension View {
    func entrance(_ index: Int, _ shown: Bool) -> some View { modifier(Entrance(index: index, shown: shown)) }
}

// MARK: Media

private struct MediaWidget: View {
    let nowPlaying: NowPlaying
    /// Alone on Home, the player has room for the song's progress beside its controls.
    var wide = false
    let openPlayer: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: openPlayer) {
                ZStack(alignment: .bottomTrailing) {
                    Artwork(image: nowPlaying.artwork, size: 64, radius: 12)
                        .overlay {
                            if nowPlaying.artwork == nil {
                                Icon(name: "music-note-linear", size: 22).foregroundStyle(Palette.ash)
                            }
                        }
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                            .offset(x: 4, y: 4)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Open the player")

            VStack(alignment: .leading, spacing: 3) {
                // Song and artist only; the album and lyrics are a click away in the Music tab.
                if nowPlaying.hasTrack {
                    Text(nowPlaying.title)
                        .font(Typeface.title)
                        .foregroundStyle(Palette.paper)
                    Text(nowPlaying.artist)
                        .font(Typeface.body)
                        .foregroundStyle(Palette.graphite)
                } else {
                    Text("Nothing playing")
                        .font(Typeface.title)
                        .foregroundStyle(Palette.paper)
                    Text("Play music in any app")
                        .font(Typeface.caption)
                        .foregroundStyle(Palette.ash)
                }
                Spacer(minLength: 4)
                if nowPlaying.hasTrack {
                    HStack(spacing: 14) {
                        HStack(spacing: 0) {
                            IconButton(symbol: "skip-previous-bold", label: "Previous track", size: 11, box: 26) { nowPlaying.send(.previous) }
                            IconButton(symbol: nowPlaying.isPlaying ? "pause-bold" : "play-bold", label: nowPlaying.isPlaying ? "Pause" : "Play", size: 14, box: 28) {
                                nowPlaying.send(.togglePlayPause)
                            }
                            IconButton(symbol: "skip-next-bold", label: "Next track", size: 11, box: 26) { nowPlaying.send(.next) }
                        }
                        .padding(.leading, -7) // optically align the first icon with the text, not its hover circle
                        if wide {
                            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                                ProgressRow(time: nowPlaying.position(at: context.date), duration: nowPlaying.duration,
                                            accent: Color(nsColor: nowPlaying.accent))
                            }
                        }
                    }
                }
            }
            .lineLimit(1)
            .contentTransition(.opacity)
            .animation(Motion.easeOut(0.25), value: nowPlaying.trackKey)
            .frame(height: 64 + 4, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.easeOut(0.25), value: nowPlaying.appBundleID)
    }

    /// The playing app's own icon, badged onto the artwork so you can tell Spotify from Music at a glance.
    private var appIcon: NSImage? {
        nowPlaying.appBundleID
            .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

// MARK: Calendar

private struct WeekWidget: View {
    let agenda: Agenda
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selected.formatted(.dateTime.month(.wide)))
                .font(Typeface.title)
                .foregroundStyle(Palette.paper)
                .contentTransition(.opacity)
            HStack(spacing: 0) {
                ForEach(agenda.weekDays, id: \.self) { day in
                    DayCell(day: day, selected: Calendar.current.isDate(day, inSameDayAs: selected),
                            hasEvents: agenda.access == .granted && !agenda.events(on: day).isEmpty, namespace: selection) {
                        withAnimation(Motion.snappy) { selected = day }
                    }
                }
            }
            dayDetail
                .id(selected)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var dayDetail: some View {
        switch agenda.access {
        case .granted:
            let events = agenda.events(on: selected)
            if events.isEmpty {
                Label {
                    Text(Calendar.current.isDateInToday(selected) ? "Nothing else today" : "Nothing on \(selected.formatted(.dateTime.weekday(.wide)))")
                } icon: {
                    Icon(name: "calendar-linear", size: 13)
                }
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.ash)
                    .padding(.top, 2)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(events.prefix(2), id: \.calendarItemIdentifier) { EventLine(event: $0) }
                    if events.count > 2 {
                        Text("\(events.count - 2) more").font(Typeface.caption).foregroundStyle(Palette.ash)
                    }
                }
            }
        case .denied:
            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            } label: {
                Label { Text("Allow calendar access") } icon: { Icon(name: "calendar-linear", size: 13) }
            }
            .buttonStyle(LinkStyle())
        case .unknown:
            Button { Task { await agenda.refresh() } } label: {
                Label { Text("Connect calendar") } icon: { Icon(name: "calendar-linear", size: 13) }
            }
            .buttonStyle(LinkStyle())
        }
    }
}

private struct DayCell: View {
    let day: Date
    let selected: Bool
    let hasEvents: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        let today = Calendar.current.isDateInToday(day)
        Button(action: action) {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(Typeface.micro)
                    .foregroundStyle(Palette.ash)
                Text(day.formatted(.dateTime.day()))
                    .font(Typeface.value)
                    .foregroundStyle(today || selected ? Palette.paper : Palette.graphite)
                    .frame(width: 22, height: 22)
                    .background {
                        if selected { Circle().fill(Palette.rail).matchedGeometryEffect(id: "day", in: namespace) }
                        if today { Circle().fill(Color(nsColor: .controlAccentColor)) } // your Mac's own accent color
                    }
                Circle()
                    .fill(Palette.ash)
                    .frame(width: 3, height: 3)
                    .opacity(hasEvents ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (hasEvents ? ", has events" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A quiet inline action: grey until hovered, so it doesn't compete with the content around it.
private struct LinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LinkLabel(configuration: configuration)
    }

    private struct LinkLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Typeface.caption.weight(.semibold))
                .foregroundStyle(hovering ? Palette.paper : Palette.graphite)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .padding(.top, 2)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(Motion.ease(0.15), value: hovering)
        }
    }
}

// MARK: Quick actions and status

private struct QuickActions: View {
    let app: NotchController

    /// In order of urgency: muting is the one you reach for in a hurry.
    enum Action: CaseIterable {
        case mic, awake, screenshot, color, output

        var tool: Tool {
            switch self {
            case .mic: .micMute
            case .awake: .keepAwake
            case .screenshot: .screenshot
            case .color: .colorPicker
            case .output: .audioOutput
            }
        }
    }

    private var actions: [Action] { Action.allCases.filter { app.preferences.isOn($0.tool) } }

    static func hasActions(_ app: NotchController) -> Bool {
        Action.allCases.contains { app.preferences.isOn($0.tool) }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(actions, id: \.self) { button(for: $0) }
        }
        .fixedSize()
    }

    @ViewBuilder private func button(for action: Action) -> some View {
        switch action {
        case .mic:
            let muted = app.microphone.isMuted
            IconButton(symbol: muted ? "microphone-bold" : "microphone-linear", label: muted ? "Unmute microphone" : "Mute microphone", size: 12, box: 28, active: muted, plate: true) {
                app.microphone.toggle()
            }
            .help(muted ? "Microphone muted (⌃⌥M)" : "Mute microphone (⌃⌥M)")
        case .awake:
            let on = app.keepAwake.isOn
            // An open eye: your Mac stays awake while it's lit.
            IconButton(symbol: on ? "eye-bold" : "eye-linear", label: on ? "Let Mac sleep" : "Keep Mac awake", size: 12, box: 28, active: on, plate: true) {
                app.keepAwake.toggle()
            }
            .help(on ? "Keeping your Mac awake" : "Keep your Mac awake")
        case .screenshot:
            IconButton(symbol: "camera-linear", label: "Take a screenshot", size: 12, box: 28, plate: true) { app.takeScreenshot() }
                .help("Take a screenshot (⌃⌥S)")
        case .color:
            IconButton(symbol: "pipette-linear", label: "Pick a color", size: 12, box: 28, plate: true) { app.pickColor() }
                .help("Pick a color on screen (⌃⌥P)")
        case .output:
            OutputMenu(outputs: app.audioOutputs)
        }
    }
}

/// One line of everything else, each piece opening its tool. Pieces only appear when they have something to say.
private struct StatusRow: View {
    let app: NotchController
    let open: (Tool) -> Void

    var body: some View {
        // One clock for the whole row: the timer chip needs seconds, the world clock minutes.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            // In your personas' order. Chips that don't fit are left out whole, least important first,
            // rather than every chip being squeezed into "…".
            PriorityRow(spacing: 16) {
                ForEach(app.preferences.layout.chips, id: \.self) { kind in
                    chip(for: kind, at: context.date)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 20)
        .clipped()
    }

    static func hasChips(_ app: NotchController) -> Bool {
        app.preferences.layout.chips.contains { shows($0, app) }
    }

    /// Whether a chip has something to say right now. Battery is everyone's; the rest follow their tool.
    static func shows(_ kind: StatusChip, _ app: NotchController) -> Bool {
        let isOn = app.preferences.isOn
        switch kind {
        case .timer: return isOn(.timer) && app.countdown.isActive
        case .shelf: return isOn(.shelf) && !app.shelf.files.isEmpty
        case .clipboard: return isOn(.clipboard) && !app.clipboard.entries.isEmpty
        case .battery: return app.stats.battery != nil
        case .cpu: return isOn(.stats) && app.stats.cpu != nil
        case .claude: if case .limit = app.usage.claude { return isOn(.stats) && app.usage.showsClaude } else { return false }
        case .codex: if case .limit = app.usage.codex { return isOn(.stats) && app.usage.showsCodex } else { return false }
        case .clocks: return isOn(.worldClock) && !app.worldClock.zones.isEmpty
        }
    }

    @ViewBuilder private func chip(for kind: StatusChip, at date: Date) -> some View {
        switch kind {
        case _ where !Self.shows(kind, app):
            EmptyView()
        case .timer:
            chip("stopwatch-linear", Countdown.format(app.countdown.remaining(at: date)), tint: .orange, opens: .timer)
        case .shelf:
            chip("inbox-linear", app.shelf.files.count == 1 ? "1 file" : "\(app.shelf.files.count) files", opens: .shelf)
        case .clipboard:
            chip("copy-linear", "\(app.clipboard.entries.count) copied", opens: .clipboard)
        case .battery:
            let battery = app.stats.battery!
            chip(battery.onPower ? "battery-charge-linear" : "battery-full-linear", "\(battery.percent)%", opens: .stats)
        case .cpu:
            chip("cpu-linear", "\(Int((app.stats.cpu! * 100).rounded()))%", opens: .stats)
        case .claude:
            if case .limit(let limit) = app.usage.claude {
                chip("claude-logo", "Claude \(Int(limit.percent.rounded()))%", warn: limit.percent >= 90, opens: .stats)
            }
        case .codex:
            if case .limit(let limit) = app.usage.codex {
                chip("codex-logo", "Codex \(Int(limit.percent.rounded()))%", warn: limit.percent >= 90, opens: .stats)
            }
        case .clocks:
            // Each city is its own chip, so the row can keep the first ones when space runs out.
            ForEach(app.worldClock.zones, id: \.self) { zone in
                Chip(symbol: zone == app.worldClock.zones.first ? "earth-linear" : nil, caption: WorldClock.city(zone),
                     text: WorldClock.time(zone, at: date), tint: Palette.ash, action: nil)
            }
        }
    }

    private func isOn(_ tool: Tool) -> Bool { app.preferences.isOn(tool) }

    private func chip(_ symbol: String, _ text: String, tint: Color = Palette.ash, warn: Bool = false, opens tool: Tool) -> some View {
        Chip(symbol: symbol, text: text, tint: warn ? Palette.warning : tint) { open(tool) }
    }
}

private struct Chip: View {
    let symbol: String?
    /// A quieter word before the value, like a city before its time.
    var caption: String?
    let text: String
    let tint: Color
    /// Nil for read-only chips like the clocks.
    let action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(PressStyle())
                .onHover { hovering = $0 }
                .animation(Motion.ease(0.15), value: hovering)
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            if let symbol { Icon(name: symbol, size: 12).foregroundStyle(tint) }
            if let caption { Text(caption).fontWeight(.medium).foregroundStyle(Palette.ash) }
            Text(text).foregroundStyle(hovering ? Palette.paper : Palette.graphite)
        }
        .font(Typeface.value)
        .lineLimit(1)
        .fixedSize() // never truncated; the row drops whole chips instead
        .contentShape(Rectangle())
    }
}

/// A row that keeps its children at full size in order, and leaves out any child that no longer
/// fits (trying the smaller ones after it), so nothing is cut off mid-word.
struct PriorityRow: SwiftUI.Layout { // SwiftUI's, not the persona Layout
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1))
        return CGSize(width: proposal.width ?? natural, height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width <= bounds.maxX + 0.5 {
                subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            } else {
                // Off to the side, out of the clipped row.
                subview.place(at: CGPoint(x: bounds.maxX + 10_000, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
            }
        }
    }
}

/// Pick where sound plays, as a native menu (it can extend past the island's edge).
private struct OutputMenu: View {
    let outputs: AudioOutputs

    var body: some View {
        Menu {
            ForEach(outputs.devices) { device in
                Button {
                    outputs.select(device)
                } label: {
                    if device.id == outputs.current { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                }
            }
        } label: {
            Icon(name: "speaker-minimalistic-linear", size: 15)
        }
        .menuStyle(.button)
        .buttonStyle(.plain) // keeps our colour; the borderless menu style draws the icon in its own
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 28, height: 28)
        .background(Circle().fill(Palette.well))
        .foregroundStyle(Palette.graphite)
        .help("Choose where sound plays")
        .accessibilityLabel("Audio output")
    }
}
