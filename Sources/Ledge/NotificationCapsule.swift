import SwiftUI

/// One persistent island surface: a notification grows the resting notch itself, keeping all
/// readable content below the camera cutout. The isolated native renderer uses this same view.
struct NotificationIsland<Content: View>: View {
    let banner: Banner?
    let notchSize: CGSize
    let restingSize: CGSize
    let expandedSize: CGSize?
    var forceReducedMotion = false
    let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forceReducedMotion }
    @State private var displayedBanner: Banner?
    @State private var progress: CGFloat = 0
    @State private var visibility: Double = 0
    @State private var generation = 0

    init(banner: Banner?, notchSize: CGSize, restingSize: CGSize, expandedSize: CGSize? = nil,
         forceReducedMotion: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.banner = banner
        self.notchSize = notchSize
        self.restingSize = restingSize
        self.expandedSize = expandedSize
        self.forceReducedMotion = forceReducedMotion
        self.content = content
    }

    var body: some View {
        let geometry = NotificationGeometry(notchSize: notchSize, restingSize: restingSize, progress: progress)
        let immediate = (banner ?? displayedBanner)?.isImmediateFeedback == true
        let motion: Animation? = reduceMotion || immediate ? nil
            : expandedSize != nil ? Motion.open : banner == nil ? Motion.notificationExit : Motion.notificationEnter
        let fade: Animation? = immediate ? nil : reduceMotion ? Motion.notificationFade
            : banner == nil ? Motion.notificationExit : Motion.notificationFade
        NotificationIslandPresentation(banner: displayedBanner, notchHeight: notchSize.height,
                                       size: expandedSize ?? geometry.size,
                                       cornerProgress: expandedSize == nil ? progress : 1,
                                       progress: progress, visibility: visibility,
                                       expanded: expandedSize != nil,
                                       moves: !reduceMotion && displayedBanner?.isImmediateFeedback != true,
                                       fadeAnimation: fade,
                                       content: content())
            .animation(motion, value: progress)
            .onChange(of: banner, initial: true) { _, incoming in present(incoming) }
    }

    private func present(_ incoming: Banner?) {
        generation += 1
        let currentGeneration = generation
        let immediate = (incoming ?? displayedBanner)?.isImmediateFeedback == true
        var instant = Transaction(animation: nil)
        instant.disablesAnimations = true
        // Keep content mounted through the return to the resting size. A replacement never
        // inserts another surface, and cannot be removed by an earlier dismissal completion.
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
            if incoming == nil, generation == currentGeneration { displayedBanner = nil }
        }
    }
}

/// Geometry is shared with regression checks. There is no gap or second silhouette: the surface
/// remains attached to y=0, and its minimum height always covers the physical camera cutout.
struct NotificationGeometry {
    let notchSize: CGSize
    let restingSize: CGSize
    var progress: CGFloat

    var notificationSize: CGSize {
        CGSize(width: max(NotificationCapsule.width, notchSize.width + 28),
               height: notchSize.height + NotificationCapsule.height)
    }

    var size: CGSize {
        CGSize(width: max(notchSize.width, restingSize.width + (notificationSize.width - restingSize.width) * progress),
               height: max(notchSize.height, restingSize.height + (notificationSize.height - restingSize.height) * progress))
    }

    /// Only the bottom edge yields, then returns to its normal contour at either resting state.
    static func bend(at progress: CGFloat) -> CGFloat { 32 * progress * (1 - progress) }

    /// Labels reveal once the surface has enough space for the unscaled badge and text.
    static func contentReveal(at progress: CGFloat) -> Double {
        Double(min(1, max(0, (progress - 0.85) / 0.15)))
    }
}

/// Interpolated values reach the shape directly, so the jelly contour follows the actual spring
/// rather than animating a second time. Text keeps its natural proportions throughout the morph.
private struct NotificationIslandPresentation<Content: View>: View, Animatable {
    let banner: Banner?
    let notchHeight: CGFloat
    var size: CGSize
    var cornerProgress: CGFloat
    var progress: CGFloat
    let visibility: Double
    let expanded: Bool
    let moves: Bool
    let fadeAnimation: Animation?
    let content: Content

    typealias AnimatableData = AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>

    var animatableData: AnimatableData {
        get { AnimatablePair(AnimatablePair(size.width, size.height),
                            AnimatablePair(cornerProgress, progress)) }
        set {
            size = CGSize(width: newValue.first.first, height: newValue.first.second)
            cornerProgress = newValue.second.first
            progress = newValue.second.second
        }
    }

    var body: some View {
        let phase = min(1.08, max(0, progress))
        let corner = min(1, max(0, cornerProgress))
        let surface = NotchShape(topRadius: 6 + 8 * corner, bottomRadius: 12 + 20 * corner,
                                 bend: expanded || !moves ? 0 : NotificationGeometry.bend(at: phase))
        let reveal = moves ? NotificationGeometry.contentReveal(at: phase) : 1
        ZStack(alignment: .top) {
            surface.fill(.black)
            content.opacity(expanded ? 1 : 1 - visibility)
                .animation(fadeAnimation, value: visibility)
            if let banner {
                NotificationCapsule(banner: banner)
                    .transaction { $0.animation = nil; $0.disablesAnimations = true }
                    .padding(.top, notchHeight)
                    .opacity(expanded ? 0 : visibility * reveal)
                    .animation(fadeAnimation, value: visibility)
                    .allowsHitTesting(false)
                    .accessibilityHidden(expanded || visibility == 0)
            }
        }
        .frame(width: max(1, size.width), height: max(notchHeight, size.height), alignment: .top)
        .clipShape(surface)
        .overlay {
            surface.stroke(.white.opacity(expanded ? 0 : visibility * 0.10), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(expanded ? 0 : visibility * 0.22), radius: 10, x: 0, y: 6)
    }
}

/// Readable notification content only. Its parent is the one shared notch surface.
struct NotificationCapsule: View {
    static let width: CGFloat = 364
    static let height: CGFloat = 64
    static let shadowSpace: CGFloat = 24

    let banner: Banner

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
        .padding(.leading, 24)
        .padding(.trailing, 26)
        .frame(width: Self.width, height: Self.height)
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
