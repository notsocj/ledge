import SwiftUI

struct NotchView: View {
    let app: NotchController
    @State private var lyrics: [LyricLine]? // nil while looking them up
    @State private var tabDirection: CGFloat = 1
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: NotchModel { app.model }
    private var nowPlaying: NowPlaying { app.nowPlaying }

    var body: some View {
        let size = shapeSize
        ZStack(alignment: .top) {
            Color.black
            if model.expanded {
                expanded.transition(.asymmetric(insertion: .reveal, removal: .opacity.animation(Motion.easeOut(0.12))))
            } else {
                closed.transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(NotchShape(topRadius: model.expanded ? 14 : 6, bottomRadius: model.expanded ? 32 : 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : Motion.open, value: closedContent) // wings follow what they show
        .task(id: nowPlaying.trackKey) {
            lyrics = nil
            guard nowPlaying.hasTrack else { return }
            if Snapshots.folder != nil { lyrics = Snapshots.demoLyrics; return }
            let found = await LRCLIB.syncedLyrics(title: nowPlaying.title, artist: nowPlaying.artist, album: nowPlaying.album, duration: nowPlaying.duration)
            if !Task.isCancelled { lyrics = found }
        }
    }

    /// What the closed island shows beside the notch, most urgent first.
    private enum Closed: Equatable {
        case banner(Banner), micMuted, inUse, timer, media, nothing
    }

    private var closedContent: Closed {
        if let banner = model.banner { return .banner(banner) }
        // A muted mic outranks everything: it's what you need to know before you speak.
        if app.preferences.isOn(.micMute), app.microphone.isMuted { return .micMuted }
        if app.preferences.isOn(.inUse), app.inUse.any { return .inUse }
        for activity in app.preferences.layout.closedOrder {
            switch activity {
            case .timer where app.preferences.isOn(.timer) && app.countdown.isActive: return .timer
            case .media where app.preferences.isOn(.media) && nowPlaying.hasTrack: return .media
            default: continue
            }
        }
        return .nothing
    }

    private var shapeSize: CGSize {
        if model.expanded { return model.expandedSize }
        let wing: CGFloat = switch closedContent {
        case .banner(.meeting), .banner(.agent): 124
        case .inUse: 64
        case .banner: 96
        case .micMuted: 64
        case .timer: 64
        case .media: 44
        case .nothing: 0
        }
        return CGSize(width: model.notchSize.width + wing * 2, height: model.notchSize.height)
    }

    // MARK: Closed

    @ViewBuilder private var closed: some View {
        switch closedContent {
        case .banner(let banner):
            BannerView(banner: banner, height: model.notchSize.height)
        case .micMuted:
            Wings(height: model.notchSize.height) {
                MicIcon(muted: true, size: 15).foregroundStyle(.red)
            } trailing: {
                Text("Muted").foregroundStyle(.red)
            }
            .accessibilityLabel("Microphone muted")
        case .inUse:
            // Green for camera, orange for microphone: the colours macOS uses for the same thing.
            Wings(height: model.notchSize.height) {
                HStack(spacing: 6) {
                    if app.inUse.camera { Icon(name: "videocamera-linear", size: 15).foregroundStyle(.green) }
                    if app.inUse.microphone { MicIcon(muted: false, size: 15).foregroundStyle(.orange) }
                }
            } trailing: {
                Text(app.inUse.camera ? "Live" : "Mic on").foregroundStyle(app.inUse.camera ? .green : .orange)
            }
            .accessibilityLabel(app.inUse.camera ? "Camera in use" : "Microphone in use")
        case .timer:
            Wings(height: model.notchSize.height) {
                let onBreak = app.countdown.focus?.onBreak == true
                Icon(name: onBreak ? "leaf-linear" : "stopwatch-bold", size: 15).foregroundStyle(onBreak ? .green : .orange)
            } trailing: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Countdown.format(app.countdown.remaining(at: context.date)))
                }
            }
        case .media:
            Wings(height: model.notchSize.height) {
                Artwork(image: nowPlaying.artwork, size: model.notchSize.height - 12, radius: 5)
            } trailing: {
                Icon(name: "soundwave-bold", size: 16)
                    .foregroundStyle(Color(nsColor: nowPlaying.accent))
                    .opacity(nowPlaying.isPlaying ? 1 : 0.5)
                    .animation(Motion.ease(0.2), value: nowPlaying.isPlaying)
                    .accessibilityLabel(nowPlaying.isPlaying ? "Playing" : "Paused")
            }
        case .nothing:
            EmptyView()
        }
    }

    // MARK: Open

    @ViewBuilder private var expanded: some View {
        if let flow = model.onboarding {
            VStack(spacing: 0) {
                OnboardingStrip(step: flow.step)
                    .frame(height: model.notchSize.height)
                    .padding(.horizontal, 22)
                OnboardingView(app: app, flow: flow)
                    .fixedSize(horizontal: false, vertical: true)
                    .background { GeometryReader { Color.clear.preference(key: OnboardingHeight.self, value: $0.size.height) } }
                    .padding(.top, NotchModel.contentInsets.top)
                    .padding(.horizontal, 24)
                    .padding(.bottom, NotchModel.contentInsets.bottom)
            }
            .frame(width: NotchModel.width, height: model.expandedSize.height, alignment: .top)
            .onPreferenceChange(OnboardingHeight.self) { app.measuredOnboarding($0) }
        } else {
            tabbed
        }
    }

    private var tabbed: some View {
        VStack(spacing: 0) {
            // Tab pills on both sides of the notch. One namespace, so the selection pill travels
            // between them, passing behind the notch.
            HStack(spacing: 0) {
                TabPills(tabs: app.leftTabs, selection: model.tab, namespace: pill, select: select)
                Spacer(minLength: model.notchSize.width + 16)
                TabPills(tabs: app.rightTabs, selection: model.tab, namespace: pill, select: select)
            }
            .frame(height: model.notchSize.height)
            .padding(.horizontal, 20)

            tabContent
                .fixedSize(horizontal: false, vertical: true) // natural height, which sizes the island
                .background { GeometryReader { Color.clear.preference(key: TabHeights.self, value: [model.tab: $0.size.height]) } }
                .id(model.tab)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .opacity.combined(with: .offset(x: tabDirection * 10)), // from the side it was picked on
                    removal: .opacity.animation(Motion.easeOut(0.1))))
                .padding(.top, NotchModel.contentInsets.top)
                .padding(.horizontal, 24)
                .padding(.bottom, NotchModel.contentInsets.bottom)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(width: NotchModel.width, height: model.expandedSize.height, alignment: .top)
        .onPreferenceChange(TabHeights.self) { app.measured($0) }
    }

    private func select(_ tab: Tool) {
        guard tab != model.tab else { return }
        let tabs = app.tabs
        tabDirection = (tabs.firstIndex(of: tab) ?? 0) > (tabs.firstIndex(of: model.tab) ?? 0) ? 1 : -1
        withAnimation(reduceMotion ? Motion.easeOut(0.15) : Motion.snappy) { model.tab = tab }
    }

    @ViewBuilder private var tabContent: some View {
        switch model.tab {
        case .home: HomeView(app: app)
        case .media: MediaTab(nowPlaying: nowPlaying, lyrics: lyrics)
        case .shelf: ShelfView(shelf: app.shelf)
        case .colorPicker: ColorsView(picker: app.colorPicker) { app.pickColor() }
        case .ports: PortsView(ports: app.ports)
        case .clipboard: ClipboardView(history: app.clipboard)
        case .timer: TimerView(countdown: app.countdown)
        case .notes: NotesView(notes: app.notes)
        case .stats: StatsView(stats: app.stats, usage: app.usage)
        default: EmptyView()
        }
    }
}

private struct OnboardingHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Each tab reports its own height under its own key, so during a tab switch the outgoing and
/// incoming tabs can't overwrite each other's measurement.
private struct TabHeights: PreferenceKey {
    static let defaultValue: [Tool: CGFloat] = [:]
    static func reduce(value: inout [Tool: CGFloat], nextValue: () -> [Tool: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Tabs as pills: the selected one shows its label, the rest shrink to icons so seven fit beside the notch.
private struct TabPills: View {
    let tabs: [Tool]
    let selection: Tool
    let namespace: Namespace.ID
    let select: (Tool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                TabPill(tab: tab, selected: tab == selection, namespace: namespace) { select(tab) }
            }
        }
    }
}

private struct TabPill: View {
    let tab: Tool
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Icon(name: tab.symbol, size: 13)
                if selected {
                    Text(tab.shortTitle)
                        .font(Typeface.label)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .foregroundStyle(selected || hovering ? Palette.paper : Palette.ash)
            .padding(.horizontal, selected ? 9 : 5)
            .frame(minWidth: 23, minHeight: 22)
            .background {
                if selected {
                    Capsule().fill(Palette.rail).matchedGeometryEffect(id: "pill", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.ease(0.15), value: hovering)
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct BannerView: View {
    let banner: Banner
    let height: CGFloat

    var body: some View {
        Wings(height: height) {
            switch banner {
            case .level(let symbol, _): Icon(name: symbol, size: 16)
            case .battery(let percent, let charging):
                Icon(name: charging ? "battery-charge-bold" : "battery-low-bold", size: 17)
                    .foregroundStyle(charging ? .green : percent <= 20 ? Palette.warning : Palette.paper)
            case .headphones: Icon(name: "headphones-round-bold", size: 16)
            case .screenshot(let image): Artwork(image: image, size: height - 12, radius: 4)
            case .message(let symbol, _): Icon(name: symbol, size: 16)
            case .color(let hex):
                Circle()
                    .fill(Color(nsColor: ColorPicker.color(hex: hex) ?? .gray))
                    .overlay(Circle().strokeBorder(Palette.ash, lineWidth: 1))
                    .frame(width: 15, height: 15)
            case .meeting(let title, _):
                HStack(spacing: 6) {
                    Icon(name: "calendar-mark-linear", size: 15)
                    Text(title).frame(maxWidth: 98, alignment: .leading)
                }
            case .mic(let muted): MicIcon(muted: muted, size: 15).foregroundStyle(muted ? .red : Palette.paper)
            case .agent(let name, _, let project):
                HStack(spacing: 6) {
                    Icon(name: name == "Claude" ? "claude-logo" : "codex-logo", size: 15)
                    Text(project.isEmpty ? name : project).frame(maxWidth: 98, alignment: .leading)
                }
            }
        } trailing: {
            switch banner {
            case .level(_, let value):
                Capsule()
                    .fill(Palette.rail)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule().fill(Palette.paper).frame(width: geometry.size.width * value)
                        }
                    }
                    .frame(width: 56, height: 4)
                    .animation(Motion.easeOut(0.15), value: value)
                    .accessibilityLabel("\(Int((value * 100).rounded())) percent")
            case .battery(let percent, _): Text("\(percent)%")
            case .headphones(_, let battery): Text(battery.map { "\($0)%" } ?? "Connected")
            case .screenshot: Text("Copied")
            case .message(_, let text): Text(text)
            case .color(let hex): Text(hex)
            case .meeting(_, let startsAt): Text("in \(max(1, Int((startsAt.timeIntervalSinceNow / 60).rounded(.up)))) min")
            case .mic(let muted): Text(muted ? "Muted" : "Mic on")
            case .agent(_, let waiting, _): Text(waiting ? "Needs you" : "Done").foregroundStyle(waiting ? .orange : Palette.paper)
            }
        }
    }
}

/// A microphone, struck through while muted (Solar has no muted-microphone icon).
struct MicIcon: View {
    let muted: Bool
    var size: CGFloat = 15

    var body: some View {
        Icon(name: "microphone-linear", size: size)
            .overlay {
                if muted {
                    Capsule().frame(width: 1.8, height: size * 1.15).rotationEffect(.degrees(-45))
                }
            }
    }
}

/// Content on both sides of the physical notch while the island is closed.
struct Wings<Leading: View, Trailing: View>: View {
    let height: CGFloat
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            leading
            Spacer()
            trailing
        }
        .font(Typeface.wing)
        .foregroundStyle(Palette.paper)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: height)
    }
}

/// A round icon button: faint circle on hover, a slight press-down, and symbol morphs on change.
struct IconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 15
    var box: CGFloat = 36
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Icon(name: symbol, size: size + 3)
                .id(symbol)
                .transition(.blurReplace) // play ⇄ pause and similar swaps blur into each other
                .frame(width: box, height: box)
                .background(Circle().fill(Palette.rail).opacity(hovering || active ? 1 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        // Big media controls are always white; small utility buttons stay quiet until used.
        .foregroundStyle(active || hovering || box >= 30 ? Palette.paper : Palette.graphite)
        .onHover { hovering = $0 }
        .animation(Motion.ease(0.15), value: hovering)
        .animation(Motion.easeOut(0.2), value: symbol)
        .accessibilityLabel(label)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Motion.easeOut(0.16), value: configuration.isPressed)
    }
}

struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            Palette.rail
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .id(ObjectIdentifier(image))
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: radius, style: .continuous))
        .animation(Motion.easeOut(0.25), value: image.map(ObjectIdentifier.init)) // crossfade on change
        .accessibilityHidden(true)
    }
}
