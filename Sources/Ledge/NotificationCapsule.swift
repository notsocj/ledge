import SwiftUI

/// Notifications live below the camera cutout, keeping the whole message in one reading line.
/// This same layer is used by the app and by the isolated native preview renderer.
struct NotificationOverlay: View {
    let banner: Banner?
    let topInset: CGFloat
    /// Allows the isolated renderer to exercise the accessible variant without changing macOS settings.
    var forceReducedMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forceReducedMotion }
    @State private var displayedBanner: Banner?
    @State private var progress: CGFloat = 0
    @State private var visibility: Double = 0
    @State private var generation = 0

    var body: some View {
        NotificationPresentation(banner: displayedBanner, progress: progress,
                                 moves: !reduceMotion && displayedBanner?.isImmediateFeedback != true)
        .opacity(visibility)
        .frame(width: NotificationCapsule.width, height: NotificationCapsule.height, alignment: .top)
        .padding(.top, topInset)
        .allowsHitTesting(false)
        .accessibilityHidden(banner == nil)
        .onChange(of: banner, initial: true) { _, incoming in present(incoming) }
    }

    private func present(_ incoming: Banner?) {
        generation += 1
        let currentGeneration = generation
        let immediate = (incoming ?? displayedBanner)?.isImmediateFeedback == true
        var instant = Transaction(animation: nil)
        instant.disablesAnimations = true
        // Retain one physical capsule throughout its exit. An interruption retargets its
        // presentation values instead of inserting a second view over the outgoing content.
        withTransaction(instant) {
            if let incoming { displayedBanner = incoming }
        }
        let target: CGFloat = incoming == nil ? 0 : 1
        if immediate || reduceMotion {
            withTransaction(instant) { progress = target }
        } else {
            withAnimation(incoming == nil ? Motion.notificationExit : Motion.notificationEnter) { progress = target }
        }
        withAnimation(immediate ? nil : reduceMotion ? Motion.notificationFade
                      : incoming == nil ? Motion.notificationExit : Motion.notificationFade,
                      completionCriteria: .removed) {
            visibility = Double(target)
        } completion: {
            // Release screenshots and stop meeting timelines after the fade. A stale completion
            // can never remove a new alert, including one that arrived halfway through dismissal.
            if incoming == nil, generation == currentGeneration { displayedBanner = nil }
        }
    }
}

/// A persistent animatable view passes the actual spring value directly into the surface.
/// Labels never inherit interpolation or crossfades when an alert replaces another one.
private struct NotificationPresentation: View, Animatable {
    let banner: Banner?
    var progress: CGFloat
    let moves: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let phase = moves ? progress : 1
        ZStack {
            if let banner {
                NotificationCapsule(banner: banner, progress: phase)
                    .transaction { $0.animation = nil; $0.disablesAnimations = true }
                    .offset(y: -18 * (1 - phase))
                    .transition(.identity)
            }
        }
    }
}

/// Only the black shell stretches; the title, badge and status keep their natural proportions.
private struct NotificationPhase {
    var progress: CGFloat = 1

    var tension: CGFloat { 1 - progress }
    // Preserve clearance around the fixed 40pt badge while the shoulders pull inward.
    var widthScale: CGFloat { 1 - 0.04 * tension }
    var heightScale: CGFloat { 1 + 0.08 * tension }
    var bend: CGFloat { 8 * tension }
}

/// Rounded shoulders stay steady while the middle yields, like a small drop of liquid.
/// At rest this is a normal capsule. Bending never changes layout or the content's hit area.
private struct NotificationSurface: Shape {
    var bend: CGFloat
    var animatableData: CGFloat {
        get { bend }
        set { bend = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.height / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX - r, y: rect.minY),
                      control1: CGPoint(x: rect.midX - r, y: rect.minY - bend * 0.3),
                      control2: CGPoint(x: rect.midX + r, y: rect.minY - bend * 0.3))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.midY), radius: r,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        path.addCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                      control1: CGPoint(x: rect.midX + r, y: rect.maxY + bend),
                      control2: CGPoint(x: rect.midX - r, y: rect.maxY + bend))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.midY), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct NotificationCapsule: View {
    static let width: CGFloat = 364
    static let height: CGFloat = 64
    static let gap: CGFloat = 10
    static let shadowSpace: CGFloat = 24

    let banner: Banner
    var progress: CGFloat = 1
    private var phase: NotificationPhase { NotificationPhase(progress: progress) }

    var body: some View {
        if case .meeting = banner {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                capsule(banner.notificationContent(at: context.date))
            }
        } else {
            capsule(banner.notificationContent())
        }
    }

    private func capsule(_ content: NotificationContent) -> some View {
        HStack(spacing: 12) {
            badge(content)
            VStack(alignment: .leading, spacing: 3) {
                Text(content.title)
                    .font(Typeface.title)
                    .foregroundStyle(Palette.paper)
                if let level = content.level {
                    Capsule()
                        .fill(Palette.rail)
                        .overlay {
                            Capsule().fill(Palette.paper).scaleEffect(x: level, anchor: .leading)
                        }
                        .frame(width: 124, height: 3)
                        .padding(.vertical, 5)
                        .accessibilityHidden(true)
                } else {
                    Text(content.detail)
                        .font(Typeface.body)
                        .foregroundStyle(Palette.graphite)
                        .truncationMode(.middle)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            if !content.status.isEmpty {
                Text(content.status)
                    .font(Typeface.headline.monospacedDigit())
                    .foregroundStyle(content.tone.color)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .frame(width: Self.width, height: Self.height)
        .background {
            let surface = NotificationSurface(bend: phase.bend)
            surface.fill(.black)
                .overlay { surface.stroke(.white.opacity(0.10), lineWidth: 0.5) }
                .overlay {
                    surface.stroke(LinearGradient(colors: [.white.opacity(0.55), .clear, .white.opacity(0.12)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        .opacity(min(1, abs(phase.tension) * 0.8))
                }
                .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 6)
                .scaleEffect(x: phase.widthScale, y: phase.heightScale, anchor: .top)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }

    private func badge(_ content: NotificationContent) -> some View {
        ZStack {
            Circle().fill(Palette.notificationBadge)
            switch banner {
            case .screenshot(let image):
                Artwork(image: image, size: 34, radius: 17)
            case .color(let hex):
                Circle()
                    .fill(Color(nsColor: ColorPicker.color(hex: hex) ?? .gray))
                    .frame(width: 30, height: 30)
            case .mic(let muted):
                MicIcon(muted: muted, size: 20).foregroundStyle(.black)
            default:
                Icon(name: content.symbol, size: 22).foregroundStyle(.black)
            }
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

struct NotificationContent: Equatable {
    enum Tone: Equatable {
        case neutral, iris, mint, amber

        var color: Color {
            switch self {
            case .neutral: Palette.paper
            case .iris: Palette.notificationIris
            case .mint: Palette.notificationMint
            case .amber: Palette.notificationAmber
            }
        }
    }

    let title: String
    let detail: String
    let status: String
    let symbol: String
    var tone: Tone = .neutral
    var level: Double?

    var accessibilityLabel: String {
        [title, detail, status].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

extension Banner {
    /// These arrive directly from keyboard shortcuts; their feedback should be immediate.
    var isImmediateFeedback: Bool {
        switch self {
        case .level, .mic, .screenshot, .color: true
        default: false
        }
    }

    func notificationContent(at now: Date = .now) -> NotificationContent {
        switch self {
        case .agent(let name, let waiting, let project):
            let context = project.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = context.isEmpty || context.allSatisfy({ $0 == "/" || $0 == "\\" })
                ? (waiting ? "Waiting for your input" : "Task completed") : context
            return NotificationContent(title: name == "Claude" ? "Claude Code" : name,
                                       detail: detail, status: waiting ? "Needs you" : "Done",
                                       symbol: name == "Claude" ? "claude-logo" : "codex-logo",
                                       tone: waiting ? .iris : .mint)
        case .meeting(let title, let startsAt):
            let seconds = startsAt.timeIntervalSince(now)
            let status = seconds <= 0 ? "Now" : "\(Int(ceil(seconds / 60))) min"
            return NotificationContent(title: "Meeting soon", detail: title, status: status,
                                       symbol: "calendar-mark-linear", tone: .iris)
        case .battery(let percent, let charging):
            return NotificationContent(title: "Battery", detail: charging ? "Power connected" : "Running on battery",
                                       status: "\(percent)%", symbol: charging ? "battery-charge-bold" : "battery-low-bold",
                                       tone: charging ? .mint : percent <= 20 ? .amber : .neutral)
        case .headphones(let name, let battery):
            return NotificationContent(title: name, detail: "Connected", status: battery.map { "\($0)%" } ?? "Ready",
                                       symbol: "headphones-round-bold", tone: .mint)
        case .level(let symbol, let value):
            let level = value.isFinite ? min(1, max(0, value)) : 0
            return NotificationContent(title: symbol == "sun-bold" ? "Brightness" : "Volume", detail: "",
                                       status: "\(Int((level * 100).rounded()))%", symbol: symbol, level: level)
        case .mic(let muted):
            return NotificationContent(title: "Microphone", detail: muted ? "You're muted" : "Ready to speak",
                                       status: muted ? "Muted" : "On", symbol: "microphone-linear", tone: muted ? .amber : .mint)
        case .color(let hex):
            return NotificationContent(title: "Color picked", detail: "Copied to clipboard", status: hex,
                                       symbol: "pallete-2-linear")
        case .screenshot:
            return NotificationContent(title: "Screenshot", detail: "Copied to clipboard", status: "Saved",
                                       symbol: "gallery-linear", tone: .mint)
        case .message(let symbol, let text):
            return NotificationContent(title: text, detail: "Ledge", status: "", symbol: symbol)
        }
    }
}
