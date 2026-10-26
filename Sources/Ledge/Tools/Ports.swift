import AppKit
import Darwin
import SwiftUI

/// What you've got listening on localhost (dev servers and the like), with Open and Stop.
/// macOS's own services and other apps' background ports are left out.
@Observable @MainActor
final class Ports {
    struct Listener: Identifiable, Equatable {
        let port: Int
        let pid: Int32
        let command: String
        var id: Int { port }
    }

    private(set) var listeners: [Listener] = []

    func refresh() async {
        let found = await Task.detached { Self.parse(Self.lsof()).filter(Self.isYours) }.value
        if found != listeners { listeners = found }
    }

    func stop(_ listener: Listener) {
        kill(listener.pid, SIGTERM) // a polite stop, like Ctrl-C; the process can clean up
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
        }
    }

    /// Parses `lsof -F pcn`: a `p` line starts each process, `c` names it, `n` lines are its addresses.
    nonisolated static func parse(_ output: String) -> [Listener] {
        var pid: Int32 = 0, command = "", seen = Set<Int>(), listeners: [Listener] = []
        for line in output.split(separator: "\n") {
            guard let kind = line.first else { continue }
            let value = line.dropFirst()
            switch kind {
            case "p": pid = Int32(value) ?? 0
            case "c": command = String(value)
            case "n":
                // "*:3000", "127.0.0.1:5173", "[::1]:5173": the port is after the last colon.
                guard let port = value.split(separator: ":").last.flatMap({ Int($0) }), !seen.contains(port),
                      port < 49152 else { continue } // 49152+ is the range apps use for private, short-lived ports
                seen.insert(port)
                listeners.append(Listener(port: port, pid: pid, command: command))
            default: continue
            }
        }
        return listeners.sorted { $0.port < $1.port }
    }

    nonisolated private static func lsof() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"] // only your own processes without sudo
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: output, as: UTF8.self)
    }

    /// Skips macOS's own services (AirPlay, sharing) and anything inside an app bundle in /Applications or /System.
    nonisolated private static func isYours(_ listener: Listener) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(listener.pid, &buffer, UInt32(buffer.count)) > 0 else { return true }
        let path = String(cString: buffer)
        return !["/System/", "/usr/libexec/", "/usr/sbin/", "/Applications/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }
}

struct PortsView: View {
    let ports: Ports

    var body: some View {
        Group {
            if ports.listeners.isEmpty {
                EmptyTab(symbol: "server-square-linear", title: "Nothing running", hint: "Dev servers you start, like npm run dev, show up here with their port.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ports.listeners.count == 1 ? "1 server on localhost" : "\(ports.listeners.count) servers on localhost")
                        .font(Typeface.caption)
                        .foregroundStyle(Palette.graphite)
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(ports.listeners) { PortRow(listener: $0, stop: { ports.stop($0) }) }
                        }
                    }
                    .frame(height: CGFloat(min(ports.listeners.count, 5)) * 34 - 2)
                    .padding(.horizontal, -10) // the rows' hover fill reaches past the text, so the dots line up with the header
                }
            }
        }
        .animation(Motion.easeOut(0.2), value: ports.listeners)
        .task {
            while !Task.isCancelled {
                await ports.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

private struct PortRow: View {
    let listener: Ports.Listener
    let stop: (Ports.Listener) -> Void
    @State private var confirming = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Palette.live)
                .frame(width: 6, height: 6)
                .accessibilityLabel("Listening")
            Text(verbatim: ":\(listener.port)") // a port, not a quantity: no thousands separator
                .font(Typeface.headline.monospacedDigit())
                .foregroundStyle(Palette.paper)
                .frame(width: 52, alignment: .leading)
            Text(listener.command)
                .font(Typeface.body)
                .foregroundStyle(Palette.graphite)
                .lineLimit(1)
            Spacer(minLength: 8)
            IconButton(symbol: "arrow-right-up-linear", label: "Open in browser", size: 11, box: 26) {
                NSWorkspace.shared.open(URL(string: "http://localhost:\(listener.port)")!)
            }
            .help("Open localhost:\(listener.port) in your browser")
            // Stopping ends someone's process, so it takes a second click to confirm.
            if confirming {
                Button("Stop it?") { stop(listener) }
                    .buttonStyle(TintedStyle())
                    .foregroundStyle(Palette.warning)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)))
            } else {
                IconButton(symbol: "stop-circle-linear", label: "Stop", size: 11, box: 26) { confirming = true }
                    .help("Stop this server")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: Radius.control + 2, style: .continuous).fill(Palette.well).opacity(hovering || confirming ? 1 : 0))
        .onHover { hovering = $0 }
        .task(id: confirming) {
            guard confirming else { return }
            try? await Task.sleep(for: .seconds(3))
            confirming = false
        }
        .animation(Motion.easeOut(0.15), value: confirming)
        .animation(Motion.ease(0.15), value: hovering)
    }
}
