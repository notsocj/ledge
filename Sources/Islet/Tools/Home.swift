import AppKit
import EventKit
import SwiftUI

/// The first thing the island shows: what's playing, your week, quick actions, and one status row
/// for everything else. Each part opens its full tool.
struct HomeView: View {
    let app: NotchController
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                if isOn(.media) { MediaWidget(nowPlaying: app.nowPlaying) { open(.media) }.entrance(0, shown) }
                if isOn(.calendar) { WeekWidget(agenda: app.agenda).entrance(1, shown) }
                Spacer(minLength: 0)
                QuickColumn(app: app).entrance(2, shown)
            }
            StatusRow(app: app, open: open).entrance(3, shown)
        }
        .onAppear { shown = true }
        .task {
            await app.agenda.refreshIfAllowed()
            app.usage.refresh()
            while !Task.isCancelled {
                app.stats.sample()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func isOn(_ tool: Tool) -> Bool { app.preferences.isOn(tool) }

    private func open(_ tool: Tool) {
        withAnimation(Motion.snappy) { app.open(tool) }
    }
}

/// Home's parts settle in one after another as the island opens: a single, short reveal.
private struct Entrance: ViewModifier {
    let index: Int
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .animation(Motion.easeOut(0.3).delay(Double(index) * 0.05), value: shown)
    }
}

private extension View {
    func entrance(_ index: Int, _ shown: Bool) -> some View { modifier(Entrance(index: index, shown: shown)) }
}

// MARK: Media

private struct MediaWidget: View {
    let nowPlaying: NowPlaying
    let openPlayer: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: openPlayer) {
                ZStack(alignment: .bottomTrailing) {
                    Artwork(image: nowPlaying.artwork, size: 72, radius: 12)
                        .overlay {
                            if nowPlaying.artwork == nil {
                                Icon(name: "music-note-linear", size: 22).foregroundStyle(Palette.ash)
                            }
                        }
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 22, height: 22)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                            .offset(x: 5, y: 5)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Open the player")

            VStack(alignment: .leading, spacing: 2) {
                if nowPlaying.hasTrack {
                    Text(nowPlaying.title)
                        .font(Typeface.title)
                        .foregroundStyle(Palette.paper)
                    Text(nowPlaying.artist)
                        .font(Typeface.body)
                        .foregroundStyle(Palette.graphite)
                    if !nowPlaying.album.isEmpty {
                        Text(nowPlaying.album)
                            .font(Typeface.caption)
                            .foregroundStyle(Palette.ash)
                    }
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
                    HStack(spacing: 0) {
                        IconButton(symbol: "skip-previous-bold", label: "Previous track", size: 11, box: 26) { nowPlaying.send(.previous) }
                        IconButton(symbol: nowPlaying.isPlaying ? "pause-bold" : "play-bold", label: nowPlaying.isPlaying ? "Pause" : "Play", size: 14, box: 28) {
                            nowPlaying.send(.togglePlayPause)
                        }
                        IconButton(symbol: "skip-next-bold", label: "Next track", size: 11, box: 26) { nowPlaying.send(.next) }
                    }
                    .offset(x: -7) // optically align the first icon with the text, not its hover circle
                }
            }
            .lineLimit(1)
            .contentTransition(.opacity)
            .animation(Motion.easeOut(0.25), value: nowPlaying.trackKey)
            .frame(height: 72 + 4, alignment: .topLeading)
        }
        .frame(width: 222, alignment: .leading)
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
        .frame(width: 196, alignment: .topLeading)
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
            Button("Allow calendar access") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
            .buttonStyle(LinkStyle())
        case .unknown:
            Button("Connect your calendar") { Task { await agenda.refresh() } }
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

private struct LinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.label)
            .foregroundStyle(Palette.paper)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: Quick actions and status

private struct QuickColumn: View {
    let app: NotchController

    var body: some View {
        VStack(spacing: 2) {
            if app.preferences.isOn(.keepAwake) {
                let on = app.keepAwake.isOn
                IconButton(symbol: on ? "cup-hot-bold" : "cup-hot-linear", label: on ? "Let Mac sleep" : "Keep Mac awake", size: 12, box: 26, active: on) {
                    app.keepAwake.toggle()
                }
                .help(on ? "Keeping your Mac awake" : "Keep your Mac awake")
            }
            if app.preferences.isOn(.screenshot) {
                IconButton(symbol: "camera-linear", label: "Take a screenshot", size: 12, box: 26) { app.takeScreenshot() }
                    .help("Take a screenshot (⌃⌥S)")
            }
            if app.preferences.isOn(.menuBarHider) {
                // macOS 26+ draws every app's menu bar icon itself and ignores the old trick of pushing icons
                // off-screen, so hiding them is a system setting now: send people straight to it.
                IconButton(symbol: "hamburger-menu-linear", label: "Choose menu bar icons", size: 12, box: 26) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
                }
                .help("Choose which icons show in the menu bar")
            }
        }
    }
}

/// One line of everything else, each piece opening its tool. Pieces only appear when they have something to say.
private struct StatusRow: View {
    let app: NotchController
    let open: (Tool) -> Void

    var body: some View {
        HStack(spacing: 14) {
            if isOn(.timer), app.countdown.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    chip("stopwatch-linear", Countdown.format(app.countdown.remaining(at: context.date)), tint: .orange, opens: .timer)
                }
            }
            if isOn(.shelf), !app.shelf.files.isEmpty {
                chip("inbox-linear", app.shelf.files.count == 1 ? "1 file" : "\(app.shelf.files.count) files", opens: .shelf)
            }
            if isOn(.clipboard), !app.clipboard.entries.isEmpty {
                chip("copy-linear", "\(app.clipboard.entries.count) copied", opens: .clipboard)
            }
            if isOn(.stats) {
                if let battery = app.stats.battery {
                    chip(battery.onPower ? "battery-charge-linear" : "battery-full-linear", "\(battery.percent)%", opens: .stats)
                }
                if let cpu = app.stats.cpu {
                    chip("cpu-linear", "\(Int((cpu * 100).rounded()))%", opens: .stats)
                }
                if app.usage.showsClaude, case .limit(let limit) = app.usage.claude {
                    chip("stars-minimalistic-linear", "Claude \(Int(limit.percent.rounded()))%", warn: limit.percent >= 90, opens: .stats)
                }
                if app.usage.showsCodex, case .limit(let limit) = app.usage.codex {
                    chip("code-linear", "Codex \(Int(limit.percent.rounded()))%", warn: limit.percent >= 90, opens: .stats)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 18)
    }

    private func isOn(_ tool: Tool) -> Bool { app.preferences.isOn(tool) }

    private func chip(_ symbol: String, _ text: String, tint: Color = Palette.ash, warn: Bool = false, opens tool: Tool) -> some View {
        Chip(symbol: symbol, text: text, tint: warn ? Palette.warning : tint) { open(tool) }
    }
}

private struct Chip: View {
    let symbol: String
    let text: String
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Icon(name: symbol, size: 12).foregroundStyle(tint)
                Text(text).foregroundStyle(hovering ? Palette.paper : Palette.graphite)
            }
            .font(Typeface.value)
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.ease(0.15), value: hovering)
    }
}
