import AppKit
import SwiftUI

/// Native, deterministic review images. Never starts a service or reads/writes user preferences.
@MainActor enum F1Preview {
    static var isRequested: Bool { CommandLine.arguments.contains("--f1-preview") }

    static func startIfRequested() -> Bool {
        guard isRequested else { return false }
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--f1-preview"), index + 1 < args.count,
              !args[index + 1].hasPrefix("--") else {
            print("Usage: Ledge --f1-preview <folder>")
            NSApp.terminate(nil)
            return true
        }
        let folder = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        Task {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let weekend = F1Companion(snapshot: .preview, now: F1Snapshot.previewNow, cacheURL: nil)
                let pending = F1Companion(snapshot: .preview, now: F1Snapshot.preview.races[0].start!.addingTimeInterval(3600), cacheURL: nil)
                let empty = F1Companion(cacheURL: nil)
                let offseason = F1Companion(snapshot: .preview,
                    now: F1Snapshot.preview.races[0].start!.addingTimeInterval(-(120 * 86400 + 23 * 3600)), cacheURL: nil)
                let sample = F1Snapshot.preview.races[0]
                let unconfirmed = F1Race(season: sample.season, round: sample.round,
                    name: "Formula 1 Singapore Airlines Singapore Grand Prix", circuit: "Marina Bay Street Circuit",
                    date: sample.date, start: nil, sessions: sample.sessions.enumerated().map { index, session in
                        F1Session(id: session.id, title: index == 1 ? "Sprint qualifying" : session.title,
                                  date: session.date, start: nil)
                    })
                let unknownTimes = F1Companion(snapshot: F1Snapshot(races: [unconfirmed],
                    latestPodium: F1Snapshot.preview.latestPodium, fetchedAt: F1Snapshot.previewNow),
                    now: F1Snapshot.previewNow, cacheURL: nil)
                for (name, service, expanded) in [("weekend", weekend, true), ("pending", pending, true),
                                                  ("empty", empty, true), ("compact", weekend, false),
                                                  ("compact-pending", pending, false), ("compact-offseason", offseason, false),
                                                  ("unknown-times", unknownTimes, true)] {
                    try await capture(service, expanded: expanded, name: name, folder: folder)
                }
                print("F1 previews saved to \(folder.path)")
            } catch {
                print("F1 preview failed: \(error.localizedDescription)")
            }
            NSApp.terminate(nil)
        }
        return true
    }

    private static func capture(_ companion: F1Companion, expanded: Bool, name: String, folder: URL) async throws {
        // Measure the production content, as NotchView does, instead of keeping an oversized mock shell.
        let measurement = NSHostingView(rootView: F1View(companion: companion)
            .frame(width: NotchModel.width - 48).fixedSize(horizontal: false, vertical: true))
        let islandHeight = ceil(measurement.fittingSize.height) + 32 + NotchModel.contentInsets.top + NotchModel.contentInsets.bottom
        let size = NSSize(width: 624, height: expanded ? islandHeight + 88 : 140)
        print("\(name): island \(expanded ? 560 : 185 + F1CompactView.wingWidth(for: companion) * 2) × \(expanded ? islandHeight : 32)pt")
        let canvas = VStack(alignment: .leading, spacing: 18) {
            Text("F1 companion · Preview data")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.black.opacity(0.65))
            NotificationIsland(banner: nil, notchSize: CGSize(width: 185, height: 32),
                               restingSize: CGSize(width: 185 + F1CompactView.wingWidth(for: companion) * 2, height: 32),
                               expandedSize: expanded ? CGSize(width: 560, height: islandHeight) : nil) {
                if expanded {
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            F1Mark().frame(width: 26, height: 10)
                            Spacer()
                        }
                        .foregroundStyle(Palette.paper).padding(.horizontal, 24).frame(height: 32)
                        F1View(companion: companion)
                            .padding(.top, 8).padding(.horizontal, 24).padding(.bottom, 14)
                    }
                    .frame(width: 560, alignment: .top)
                } else {
                    F1CompactView(companion: companion, height: 32)
                }
            }
            .frame(width: 560, alignment: .top)
        }
        .padding(32).frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color(red: 0.85, green: 0.88, blue: 0.92))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        let host = NSHostingView(rootView: canvas)
        host.sizingOptions = []
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
        host.needsDisplay = true
        host.display()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("f1-\(name).png"))
    }
}
