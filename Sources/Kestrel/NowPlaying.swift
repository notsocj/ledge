import AppKit
import CoreImage
import Observation

/// System-wide now-playing state, streamed from mediaremote-adapter. macOS 15.4+ blocks the private
/// MediaRemote API for third-party apps, so the adapter runs it inside Apple's own /usr/bin/perl.
@Observable @MainActor
final class NowPlaying {
    enum Command: Int {
        case togglePlayPause = 2, next = 4, previous = 5
    }

    private(set) var title = ""
    private(set) var artist = ""
    private(set) var album = ""
    private(set) var artwork: NSImage?
    private(set) var accent: NSColor = .white
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var appBundleID: String?
    private var elapsed: TimeInterval = 0
    private var elapsedAt = Date()

    @ObservationIgnored private var state: [String: Any] = [:]
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")
    @ObservationIgnored private let framework = Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework")

    var hasTrack: Bool { !title.isEmpty }
    var trackKey: String { title + "\u{1}" + artist }

    // shortcut: assumes 1x playback speed, read payload["playbackRate"] if podcasts at 2x matter.
    func position(at date: Date) -> TimeInterval {
        isPlaying ? min(duration, elapsed + date.timeIntervalSince(elapsedAt)) : elapsed
    }

    func start() {
        guard !started else { return }
        started = true
        Task {
            var failures = 0
            while failures < 5 {
                if await stream() { failures = 0 } else { failures += 1 }
                try? await Task.sleep(for: .seconds(2))
            }
            print("Kestrel: mediaremote-adapter keeps failing; now playing disabled")
        }
    }

    func stop() {
        process?.terminate()
    }

    func send(_ command: Command) {
        if command == .togglePlayPause, hasTrack {
            // Flip now so the button answers instantly; the adapter's next update confirms or corrects it.
            elapsed = position(at: .now)
            elapsedAt = .now
            isPlaying.toggle()
        }
        _ = launch(["send", String(command.rawValue)])
    }

    /// Runs one `stream` process until it exits. Returns whether it delivered any data.
    private func stream() async -> Bool {
        let pipe = Pipe()
        guard let process = launch(["stream", "--micros", "--debounce=50"], output: pipe) else { return false }
        self.process = process
        var gotData = false
        do {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                apply(line)
                gotData = true
            }
        } catch {
            print("Kestrel: adapter stream failed: \(error)")
        }
        return gotData
    }

    private func launch(_ arguments: [String], output: Pipe? = nil) -> Process? {
        guard let script, let framework else {
            print("Kestrel: mediaremote-adapter missing from the app bundle; build with ./build.sh")
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, framework.path] + arguments
        if let output { process.standardOutput = output }
        do {
            try process.run()
            return process
        } catch {
            print("Kestrel: couldn't start perl: \(error)")
            return nil
        }
    }

    /// Each line is {"type":"data","diff":Bool,"payload":{...}}; a diff payload merges into the
    /// last state, where null means the key was removed.
    private func apply(_ line: String) {
        guard let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
        let payload = message["payload"] as? [String: Any] ?? [:]
        if message["diff"] as? Bool == true {
            for (key, value) in payload { state[key] = value is NSNull ? nil : value }
        } else {
            state = payload
        }

        title = state["title"] as? String ?? ""
        artist = state["artist"] as? String ?? ""
        album = state["album"] as? String ?? ""
        isPlaying = state["playing"] as? Bool ?? false
        appBundleID = state["bundleIdentifier"] as? String
        duration = (state["durationMicros"] as? Double ?? 0) / 1e6
        elapsed = (state["elapsedTimeMicros"] as? Double ?? 0) / 1e6
        elapsedAt = (state["timestampEpochMicros"] as? Double).map { Date(timeIntervalSince1970: $0 / 1e6) } ?? .now
        if message["diff"] as? Bool != true || payload.keys.contains("artworkData") {
            artwork = (state["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }.flatMap(NSImage.init(data:))
            accent = artwork.flatMap(Self.accent(of:)) ?? .white
        }
    }

    /// A made-up song for screenshots, so marketing images never show someone's real music.
    func showDemo(title: String, artist: String, album: String, artwork: NSImage, duration: TimeInterval, elapsed: TimeInterval) {
        (self.title, self.artist, self.album, self.artwork, self.duration, self.elapsed) = (title, artist, album, artwork, duration, elapsed)
        accent = Self.accent(of: artwork) ?? .white
        appBundleID = nil
        isPlaying = true
        elapsedAt = .now
    }

    private static let imageContext = CIContext()

    /// The artwork's average color, lifted and tamed so it stays legible on the black island.
    static func accent(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)])
        guard let average = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        imageContext.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let color = NSColor(deviceRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        return NSColor(deviceHue: color.hueComponent, saturation: min(color.saturationComponent * 1.5, 0.65), brightness: max(color.brightnessComponent, 0.85), alpha: 1)
    }
}
