import SwiftUI

/// The island is always pure black so it disappears into the hardware notch; everything on it is
/// white at a few fixed strengths, plus one accent sampled from the album art. Text strengths keep at
/// least 4.5:1 contrast on black, as Apple's guidelines ask, so even the quietest line stays readable.
enum Palette {
    static let paper = Color.white
    static let graphite = Color.white.opacity(0.64)
    static let ash = Color.white.opacity(0.46)
    /// Fills for controls and selections.
    static let rail = Color.white.opacity(0.14)
    /// A quieter surface for wells like the notes field.
    static let well = Color.white.opacity(0.07)
    static let warning = Color(nsColor: .systemOrange) // a usage limit is nearly spent
    static let live = Color(nsColor: .systemGreen) // something running right now
}

/// Corner radii nest: a shape inside the island is rounder the closer it sits to the island's own
/// 32pt corner, so curves run parallel instead of fighting.
enum Radius {
    static let control: CGFloat = 8
    static let card: CGFloat = 12
    static let well: CGFloat = 16
}

enum Motion {
    /// Opening: Apple-style spring with a little bounce, so the island feels alive.
    static let open = Animation.spring(duration: 0.5, bounce: 0.2)
    /// Closing is quicker and doesn't bounce: the user is already done with it.
    static let close = Animation.spring(duration: 0.3, bounce: 0)
    /// Selection moving between tabs or days: critically damped, so it settles without overshoot.
    static let snappy = Animation.spring(duration: 0.35, bounce: 0)
    /// Lyrics stepping up a line is on-screen movement, so ease-in-out.
    static let lyric = Animation.timingCurve(0.77, 0, 0.175, 1, duration: 0.3)

    static func move(_ duration: Double) -> Animation { .timingCurve(0.77, 0, 0.175, 1, duration: duration) }
    static func easeOut(_ duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
    static func ease(_ duration: Double) -> Animation { .timingCurve(0.25, 0.1, 0.25, 1, duration: duration) }
}

/// The hardware notch's silhouette: straight sides, rounded bottom corners, and concave top corners
/// that flare out into the screen edge. Both radii animate, so the island morphs instead of resizing.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { (topRadius, bottomRadius) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius, b = bottomRadius
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

extension AnyTransition {
    /// Content settling in as the island opens: up from a slight blur and scale, anchored at the notch.
    static var reveal: AnyTransition {
        .modifier(active: Reveal(progress: 0), identity: Reveal(progress: 1))
    }
}

private struct Reveal: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 6)
            .scaleEffect(0.96 + 0.04 * progress, anchor: .top)
    }
}

/// A Solar icon (480 Design, CC BY 4.0, via Iconify) from the app's Icons folder, tinted like text.
struct Icon: View {
    let name: String
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let image = Self.image(name) {
                Image(nsImage: image).renderingMode(Self.fullColor.contains(name) ? .original : .template).resizable().interpolation(.high)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Brand marks keep their own colours instead of being tinted like text.
    static let fullColor: Set<String> = ["claude-logo"]

    @MainActor private static var cache: [String: NSImage] = [:]

    /// SVGs load as vectors, so one file stays sharp at every size; a PNG is the fallback for artwork
    /// that only exists as an image (the Codex mark).
    @MainActor static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Icons")
                ?? Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Icons"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = !fullColor.contains(name)
        image.size = NSSize(width: 18, height: 18) // the SVGs say "1em"; give places that use the natural size (the menu bar) a real one
        cache[name] = image
        return image
    }
}

/// The type scale. Weight carries the hierarchy, so the line that matters reads first even at small
/// sizes: bold for what something is, semibold for details you scan, medium for supporting text.
enum Typeface {
    static let display = Font.system(size: 40, weight: .bold).monospacedDigit()
    static let heading = Font.system(size: 16, weight: .bold)
    static let lyric = Font.system(size: 17, weight: .bold)
    static let title = Font.system(size: 13, weight: .bold)
    static let headline = Font.system(size: 12, weight: .semibold)
    static let row = Font.system(size: 12, weight: .medium)
    static let body = Font.system(size: 11, weight: .medium)
    static let caption = Font.system(size: 10.5, weight: .medium)
    static let label = Font.system(size: 11, weight: .bold)
    static let value = Font.system(size: 11, weight: .semibold).monospacedDigit()
    static let micro = Font.system(size: 9, weight: .bold)
    static let wing = Font.system(size: 12, weight: .bold).monospacedDigit()
}

/// The one main action on a page: a white capsule.
struct PrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.label)
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(Capsule().fill(Palette.paper))
            .opacity(isEnabled ? 1 : 0.35)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.easeOut(0.16), value: configuration.isPressed)
            .animation(Motion.ease(0.15), value: isEnabled)
    }
}

/// A quieter companion to `PrimaryStyle`, for Back and Skip: plain text that brightens under the pointer.
struct SecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(configuration: configuration)
    }

    private struct HoverLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Typeface.label)
                .foregroundStyle(hovering ? Palette.paper : Palette.graphite)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { hovering = $0 }
                .animation(Motion.ease(0.15), value: hovering)
        }
    }
}

/// For actions that sit in a list beside others, like Allow on each permission: filled, but grey, so
/// the page keeps a single white button for the step forward.
struct TintedStyle: ButtonStyle {
    var height: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(configuration: configuration, height: height)
    }

    private struct HoverLabel: View {
        let configuration: ButtonStyleConfiguration
        let height: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Typeface.label)
                .foregroundStyle(Palette.paper)
                .padding(.horizontal, 12)
                .frame(height: height)
                .background(Capsule().fill(Palette.rail).opacity(hovering ? 1.6 : 1))
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .onHover { hovering = $0 }
                .animation(Motion.ease(0.15), value: hovering)
                .animation(Motion.easeOut(0.16), value: configuration.isPressed)
        }
    }
}
