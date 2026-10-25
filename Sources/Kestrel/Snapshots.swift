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

        try? await Task.sleep(for: .seconds(4)) // now playing, lyrics and usage limits load
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

        // The closed notch with each kind of banner.
        app.model.expanded = false
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

    /// The island on a dark grey backdrop, at 2x, so it reads like it does against a menu bar.
    private static func capture(_ view: NSView, _ name: String, in folder: URL) {
        view.layoutSubtreeIfNeeded()
        guard let island = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: island)
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        NSColor(white: 0.22, alpha: 1).setFill()
        NSRect(origin: .zero, size: view.bounds.size).fill()
        island.draw(in: NSRect(origin: .zero, size: view.bounds.size))
        image.unlockFocus()
        guard let data = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: folder.appending(path: "\(name).png"))
    }
}
