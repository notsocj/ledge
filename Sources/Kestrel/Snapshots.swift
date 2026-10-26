import AppKit
import SwiftUI

/// `Kestrel --snapshot <folder>` renders the island off-screen for each persona, some mixes, every tab,
/// each setup step and the closed-notch states, writes them as PNGs, and quits. Layouts are shown
/// through `Preferences.preview`, so nothing you've set is changed. For reviewing the design.
@MainActor
enum Snapshots {
    static let folder: URL? = {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }()

    /// Original lines for the demo song (no one's real lyrics on a marketing page).
    static let demoLyrics: [LyricLine] = [
        // Far apart, so whenever during a snapshot run the Music tab is captured, a next line shows too.
        LyricLine(time: 0, text: "Hold the light a little longer"),
        LyricLine(time: 50, text: "The city's turning gold behind us"),
        LyricLine(time: 100, text: "Every window catching fire"),
        LyricLine(time: 150, text: "We don't have to say we're leaving"),
        LyricLine(time: 200, text: "Stay until the street lights find us"),
    ]

    /// Demo artwork drawn in code: a low sun over dark hills.
    private static func demoArtwork() -> NSImage {
        NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
            NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.62, blue: 0.38, alpha: 1), NSColor(srgbRed: 0.52, green: 0.24, blue: 0.47, alpha: 1), NSColor(srgbRed: 0.13, green: 0.12, blue: 0.3, alpha: 1)])!
                .draw(in: rect, angle: -90)
            NSColor(srgbRed: 1, green: 0.86, blue: 0.62, alpha: 0.95).setFill()
            NSBezierPath(ovalIn: NSRect(x: 210, y: 210, width: 180, height: 180)).fill()
            NSColor(srgbRed: 0.08, green: 0.07, blue: 0.16, alpha: 1).setFill()
            let hills = NSBezierPath()
            hills.move(to: NSPoint(x: 0, y: 0)); hills.line(to: NSPoint(x: 0, y: 230))
            hills.curve(to: NSPoint(x: 330, y: 250), controlPoint1: NSPoint(x: 120, y: 300), controlPoint2: NSPoint(x: 220, y: 200))
            hills.curve(to: NSPoint(x: 600, y: 270), controlPoint1: NSPoint(x: 440, y: 300), controlPoint2: NSPoint(x: 520, y: 220))
            hills.line(to: NSPoint(x: 600, y: 0)); hills.close(); hills.fill()
            return true
        }
    }

    static func run(_ app: NotchController, into folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let size = NSSize(width: NotchModel.width, height: NotchModel.maxHeight)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -30_000, y: -30_000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        let host = NSHostingView(rootView: NotchView(app: app))
        host.sizingOptions = []
        window.contentView = host
        window.orderFrontRegardless()
        app.model.notchSize = CGSize(width: 185, height: 32) // a 14-inch MacBook Pro's notch, whatever screen this runs on

        app.nowPlaying.showDemo(title: "Afterglow", artist: "Northbound", album: "Long Way Home", artwork: demoArtwork(), duration: 214, elapsed: 5)
        try? await Task.sleep(for: .seconds(4)) // usage limits load
        app.stats.sample()
        try? await Task.sleep(for: .seconds(1))
        app.stats.sample()

        // Each persona alone, a few common mixes, and everything at once.
        let mixes: [[Persona]] = Persona.allCases.map { [$0] } + [[.developer, .designer], [.creator, .developer], [.professional, .student], Persona.allCases]
        app.model.expanded = true
        for personas in mixes {
            app.preferences.preview = personas
            let name = personas.count == Persona.allCases.count ? "all" : personas.map(\.rawValue).joined(separator: "+")
            for tab in app.tabs {
                app.model.tab = tab
                try? await Task.sleep(for: .milliseconds(700)) // tab tasks load and the island measures itself
                capture(host, "\(name)-\(tab.rawValue)", in: folder)
            }
        }

        // Setup, as a developer would see it.
        app.preferences.preview = [.developer]
        let flow = Onboarding()
        flow.toggle(.developer)
        app.model.onboarding = flow
        for step in Onboarding.Step.allCases {
            flow.go(to: step)
            try? await Task.sleep(for: .milliseconds(700))
            capture(host, "setup-\(step.rawValue)-\(step)", in: folder)
        }
        app.model.onboarding = nil

        // What the island shows once the trial is over.
        app.model.locked = true
        try? await Task.sleep(for: .milliseconds(700))
        capture(host, "trial-ended", in: folder)
        app.model.locked = false

        // The closed notch: music playing beside it, then each kind of banner.
        app.model.expanded = false
        app.preferences.preview = [.essentials] // no mic or camera indicator in front of the music
        try? await Task.sleep(for: .milliseconds(900))
        capture(host, "closed-media", in: folder)
        let banners: [(String, Banner)] = [
            ("agent-waiting", .agent(name: "Claude", waiting: true, project: "kestrel")),
            ("agent-done", .agent(name: "Codex", waiting: false, project: "website")),
            ("meeting", .meeting(title: "Design review", startsAt: .now.addingTimeInterval(110))),
            ("volume", .level(symbol: "volume-loud-bold", value: 0.6)),
            ("battery", .battery(percent: 54, charging: true)),
            ("color", .color(hex: "#FF8000")),
            ("mic", .mic(muted: true)),
        ]
        for (name, banner) in banners {
            app.model.show(banner, seconds: 60)
            try? await Task.sleep(for: .milliseconds(700))
            capture(host, "closed-\(name)", in: folder)
        }
        NSApp.terminate(nil)
    }

    /// The island at 2x on a transparent background, so it can sit on any backdrop (review sheets, the website).
    private static func capture(_ view: NSView, _ name: String, in folder: URL) {
        view.layoutSubtreeIfNeeded()
        guard let island = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: island)
        try? island.representation(using: .png, properties: [:])?.write(to: folder.appending(path: "\(name).png"))
    }
}
