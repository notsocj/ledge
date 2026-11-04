import AppKit
import SwiftUI

/// A side-effect-free preview of the production notification views. Unlike a full app snapshot,
/// this never constructs tools, reads personal content, or changes preferences.
@MainActor
enum NotificationPreview {
    static var isRequested: Bool { CommandLine.arguments.contains("--notification-preview") }

    static func startIfRequested() -> Bool {
        guard isRequested else { return false }
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--notification-preview"), index + 1 < arguments.count,
              !arguments[index + 1].hasPrefix("--") else {
            print("Usage: Ledge --notification-preview <folder> [--notification-motion]")
            NSApp.terminate(nil)
            return true
        }
        let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        Task {
            do {
                try await render(into: folder, motion: arguments.contains("--notification-motion"))
                print("Notification previews saved to \(folder.path)")
            } catch {
                print("Couldn't render notification previews: \(error.localizedDescription)")
            }
            NSApp.terminate(nil)
        }
        return true
    }

    private static func samples(at date: Date) -> [(String, Banner)] {
        [
            ("agent-done", .agent(name: "Codex", waiting: false, project: "ledge")),
            ("agent-waiting", .agent(name: "Claude", waiting: true, project: "website")),
            ("meeting", .meeting(title: "Design review", startsAt: date.addingTimeInterval(110))),
            ("battery", .battery(percent: 54, charging: true)),
            ("microphone", .mic(muted: true)),
            ("volume", .level(symbol: "volume-loud-bold", value: 0.6)),
        ]
    }

    private static func render(into folder: URL, motion: Bool) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let samples = samples(at: .now)
        let sheetSize = NSSize(width: 880, height: 470)
        let sheet = makeWindow(PreviewSheet(banners: samples.map(\.1)), size: sheetSize)
        defer { sheet.close() }
        try await Task.sleep(for: .milliseconds(250))
        try capture(sheet, to: folder.appending(path: "notifications.png"))

        let state = PreviewState()
        let window = makeWindow(PreviewDesktop(state: state), size: NSSize(width: 640, height: 260))
        defer { window.close() }
        for (name, banner) in samples {
            state.banner = banner
            try await Task.sleep(for: .milliseconds(650))
            try capture(window, to: folder.appending(path: "\(name).png"))
        }

        guard motion else { return }
        // Two full entrance/exit cycles, with enough rest between them to judge the easing.
        // The replacement stays in the same capsule, as it does in the running app.
        try await captureMotion(window, state: state, into: folder.appending(path: "frames"), count: 216,
                                updates: [(12, samples[1].1), (60, samples[0].1), (108, nil),
                                          (138, samples[3].1), (192, nil)])

        // Dismiss and re-show within the exit, then interrupt an entrance. This catches duplicated
        // capsules, jumps back to the start, or a stale exit removing the new notification.
        try await captureMotion(window, state: state, into: folder.appending(path: "interruption-frames"), count: 120,
                                updates: [(9, samples[1].1), (39, nil), (42, samples[0].1),
                                          (72, nil), (87, samples[3].1), (90, nil)])

        let reducedState = PreviewState()
        let reducedWindow = makeWindow(PreviewDesktop(state: reducedState, reduceMotion: true),
                                       size: NSSize(width: 640, height: 260))
        defer { reducedWindow.close() }
        try await captureMotion(reducedWindow, state: reducedState,
                                into: folder.appending(path: "reduced-motion-frames"), count: 90,
                                updates: [(12, samples[1].1), (48, samples[0].1), (66, nil)])
    }

    /// Native frames at 30 fps. Only the input state is scripted; the production view owns motion.
    private static func captureMotion(_ window: NSWindow, state: PreviewState, into frames: URL, count: Int,
                                      updates: [(frame: Int, banner: Banner?)]) async throws {
        state.banner = nil
        try await Task.sleep(for: .milliseconds(650))
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        // Clear only old numbered capture frames, so rendering a shorter sequence cannot leave a
        // stale tail for ffmpeg. Other files in the caller's output directory are left alone.
        for file in try FileManager.default.contentsOfDirectory(at: frames, includingPropertiesForKeys: nil) {
            let stem = file.deletingPathExtension().lastPathComponent
            if file.pathExtension == "png", stem.count == 4, stem.allSatisfy(\.isNumber) {
                try FileManager.default.removeItem(at: file)
            }
        }
        let fps = 30.0
        let start = ProcessInfo.processInfo.systemUptime
        for frame in 0..<count {
            if let update = updates.first(where: { $0.frame == frame }) {
                state.banner = update.banner
            }
            // Let SwiftUI commit each update before reading the rendered view. These frames use
            // the real transition; no screenshot is translated or composited after capture.
            let deadline = start + Double(frame + 1) / fps
            let wait = max(0.001, deadline - ProcessInfo.processInfo.systemUptime)
            try await Task.sleep(for: .seconds(wait))
            try capture(window, to: frames.appending(path: String(format: "%04d.png", frame)))
        }
    }

    private static func makeWindow<Content: View>(_ content: Content, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        host.sizingOptions = []
        window.contentView = host
        window.orderFrontRegardless()
        return window
    }

    private static func capture(_ window: NSWindow, to url: URL) throws {
        guard let view = window.contentView else { throw CaptureFailure() }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CaptureFailure() }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CaptureFailure() }
        try png.write(to: url, options: .atomic)
    }

    private struct CaptureFailure: LocalizedError {
        var errorDescription: String? { "The native view could not be captured." }
    }
}

@MainActor
private final class PreviewState: ObservableObject {
    @Published var banner: Banner?
}

private struct PreviewDesktop: View {
    @ObservedObject var state: PreviewState
    var reduceMotion = false

    var body: some View {
        ZStack(alignment: .top) {
            PreviewBackdrop()
            NotchShape(topRadius: 6, bottomRadius: 12)
                .fill(.black)
                .frame(width: 185, height: 32)
            NotificationOverlay(banner: state.banner, topInset: 42, forceReducedMotion: reduceMotion)
        }
    }
}

private struct PreviewSheet: View {
    let banners: [Banner]

    var body: some View {
        ZStack {
            PreviewBackdrop()
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ledge notifications")
                        .font(.system(size: 28, weight: .semibold))
                        .tracking(-0.7)
                    Text("A little context. Right when you need it.")
                        .font(.system(size: 14))
                        .foregroundStyle(.black.opacity(0.55))
                }
                LazyVGrid(columns: [GridItem(.fixed(364), spacing: 44), GridItem(.fixed(364))], spacing: 28) {
                    ForEach(banners.indices, id: \.self) { index in
                        NotificationCapsule(banner: banners[index])
                    }
                }
                .frame(width: 772)
            }
            .foregroundStyle(.black)
            .padding(54)
        }
    }
}

/// Presentation canvas only; notification colors and geometry come from the production component.
private struct PreviewBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.88, green: 0.90, blue: 0.93),
                                Color(red: 0.77, green: 0.81, blue: 0.86)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
