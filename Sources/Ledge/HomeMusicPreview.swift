import AppKit
import SwiftUI

/// Renders Home's real widgets with invented music, without starting the media adapter or
/// reading calendar events, preferences, clipboard contents, or any other personal data.
@MainActor
enum HomeMusicPreview {
    static var isRequested: Bool { CommandLine.arguments.contains("--home-music-preview") }

    static func startIfRequested() -> Bool {
        guard isRequested else { return false }
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--home-music-preview"), index + 1 < arguments.count,
              !arguments[index + 1].hasPrefix("--") else {
            print("Usage: Ledge --home-music-preview <folder>")
            NSApp.terminate(nil)
            return true
        }
        let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        Task {
            do {
                try await render(into: folder)
                print("Home music previews saved to \(folder.path)")
            } catch {
                print("Couldn't render Home music previews: \(error.localizedDescription)")
            }
            NSApp.terminate(nil)
        }
        return true
    }

    private static func render(into folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let player = NowPlaying()
        player.showDemo(title: "Somewhere Between Here and Home", artist: "Northbound", album: "After Hours",
                        artwork: artwork(), duration: 234, elapsed: 76)
        let empty = NowPlaying()
        let agenda = Agenda() // intentionally never refreshed: no access request or event lookup
        let samples: [(String, String, NowPlaying, [HomeWidget])] = [
            ("home-music", "Music beside your calendar", player, [.media, .week]),
            ("calendar-first", "Calendar first", player, [.week, .media]),
            ("music-only", "Music on its own", player, [.media]),
            ("music-empty", "Before playback starts", empty, [.media, .week]),
        ]
        for (name, title, nowPlaying, widgets) in samples {
            let canvas = VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.7))
                HomeWidgets(nowPlaying: nowPlaying, agenda: agenda, widgets: widgets, shown: true, open: { _ in })
                    .padding(24)
                    .frame(width: 560)
                    .background(.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .allowsHitTesting(false)
            }
            .padding(32)
            .frame(width: 624, height: 270, alignment: .topLeading)
            .background(Color(red: 0.85, green: 0.88, blue: 0.92))
            let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 624, height: 270),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: canvas)
            host.sizingOptions = []
            window.contentView = host
            window.orderFrontRegardless()
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(350))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CaptureFailure() }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CaptureFailure() }
            try data.write(to: folder.appending(path: "\(name).png"), options: .atomic)
        }
    }

    /// Original artwork for previews: a cool evening sky over water.
    private static func artwork() -> NSImage {
        NSImage(size: NSSize(width: 400, height: 400), flipped: false) { rect in
            NSGradient(colors: [NSColor(srgbRed: 0.12, green: 0.26, blue: 0.42, alpha: 1),
                                NSColor(srgbRed: 0.36, green: 0.64, blue: 0.75, alpha: 1)])!
                .draw(in: rect, angle: 90)
            NSColor(srgbRed: 0.97, green: 0.89, blue: 0.67, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 245, y: 220, width: 74, height: 74)).fill()
            NSColor(srgbRed: 0.06, green: 0.17, blue: 0.27, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 400, height: 130)).fill()
            NSColor(srgbRed: 0.75, green: 0.83, blue: 0.80, alpha: 0.5).setFill()
            for index in 0..<5 {
                NSBezierPath(roundedRect: NSRect(x: 242 - index * 5, y: 110 - index * 17,
                                               width: 78 + index * 10, height: 3), xRadius: 2, yRadius: 2).fill()
            }
            return true
        }
    }

    private struct CaptureFailure: LocalizedError {
        var errorDescription: String? { "The native Home widgets could not be captured." }
    }
}
