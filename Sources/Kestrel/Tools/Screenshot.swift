import Foundation

/// Area screenshots through macOS's own `screencapture` tool, saved to Pictures/Kestrel Screenshots.
/// macOS asks for Screen Recording permission the first time.
@MainActor
enum Screenshot {
    static func capture(then done: @escaping @MainActor (URL) -> Void) {
        let folder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appending(path: "Kestrel Screenshots")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            print("Kestrel: couldn't create the screenshots folder: \(error)")
            return
        }
        let url = folder.appending(path: "Screenshot \(fileDate.string(from: .now)).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", url.path] // interactive area or window, no shutter sound
        process.terminationHandler = { _ in
            // Pressing Escape cancels without writing a file.
            Task { @MainActor in if FileManager.default.fileExists(atPath: url.path) { done(url) } }
        }
        do {
            try process.run()
        } catch {
            print("Kestrel: couldn't start screencapture: \(error)")
        }
    }

    private static let fileDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()
}
