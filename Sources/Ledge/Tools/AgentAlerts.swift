import Foundation
import Observation

/// Lights up the notch when Claude Code or Codex finishes, or is waiting on you.
///
/// Connecting installs a tiny script and points each agent at it: Claude Code through two hooks in
/// ~/.claude/settings.json, Codex through `notify` in ~/.codex/config.toml. The script opens an
/// `ledge://agent/<agent>/<event>` link in the background, which Ledge turns into a banner.
/// Both files get a backup next to them before the first change, and disconnecting undoes it.
@Observable @MainActor
final class AgentAlerts {
    static let shared = AgentAlerts()

    enum Agent: String { case claude, codex }
    enum Status: Equatable { case notInstalled, disconnected, connected, blocked(String) }

    private(set) var claude = Status.notInstalled
    private(set) var codex = Status.notInstalled
    private(set) var lastError: String?

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var claudeSettings: URL { home.appending(path: ".claude/settings.json") }
    private var codexConfig: URL { home.appending(path: ".codex/config.toml") }
    private var support: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Ledge") }
    var script: URL { support.appending(path: "ledge-agent") }
    /// The script's name now, and before the app was renamed, so older hooks are still recognised as ours.
    nonisolated static let scriptNames = ["ledge-agent", "kestrel-agent", "islet-agent"]
    nonisolated static func isOurs(_ command: String) -> Bool { scriptNames.contains { command.contains($0) } }
    private var codexOriginal: URL { support.appending(path: "codex-notify-original.txt") }

    func refresh() {
        claude = FileManager.default.fileExists(atPath: home.appending(path: ".claude").path)
            ? (Self.claudeHooks(in: readJSON(claudeSettings) ?? [:]).isEmpty ? .disconnected : .connected) : .notInstalled
        if !FileManager.default.fileExists(atPath: home.appending(path: ".codex").path) {
            codex = .notInstalled
        } else {
            let text = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
            if let line = Self.codexNotifyLine(in: text), Self.isOurs(line) {
                codex = .connected
            } else if let line = Self.codexNotifyLine(in: text), !Self.chainable(line) {
                codex = .blocked("Codex's notify setting is written in a way Ledge can't safely change.")
            } else {
                codex = .disconnected
            }
        }
    }

    // MARK: Connect and disconnect

    func connect(_ agent: Agent) {
        lastError = nil
        do {
            try installScript()
            switch agent {
            case .claude: try connectClaude()
            case .codex: try connectCodex()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func disconnect(_ agent: Agent) {
        lastError = nil
        do {
            switch agent {
            case .claude:
                guard var settings = readJSON(claudeSettings) else { return }
                settings = Self.removingClaudeHooks(from: settings)
                try writeJSON(settings, to: claudeSettings)
            case .codex:
                var text = try String(contentsOf: codexConfig, encoding: .utf8)
                let original = try? String(contentsOf: codexOriginal, encoding: .utf8)
                text = Self.replacingNotifyLine(in: text, with: original?.isEmpty == false ? original : nil)
                try text.write(to: codexConfig, atomically: true, encoding: .utf8)
                try? FileManager.default.removeItem(at: codexOriginal)
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    private func connectClaude() throws {
        if FileManager.default.fileExists(atPath: claudeSettings.path), readJSON(claudeSettings) == nil {
            throw Failure("~/.claude/settings.json isn't valid JSON, so Ledge didn't change it.")
        }
        backUp(claudeSettings)
        var settings = Self.removingClaudeHooks(from: readJSON(claudeSettings) ?? [:])
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        // Stop: Claude finished its turn. Notification: it's asking for permission or waiting on you.
        for (event, name) in [("Stop", "done"), ("Notification", "waiting")] {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.append(["hooks": [["type": "command", "command": "\"\(script.path)\" claude \(name)"]]])
            hooks[event] = entries
        }
        settings["hooks"] = hooks
        try writeJSON(settings, to: claudeSettings)
    }

    private func connectCodex() throws {
        let text = (try? String(contentsOf: codexConfig, encoding: .utf8)) ?? ""
        var command = [script.path, "codex", "done"]
        if let line = Self.codexNotifyLine(in: text), !Self.isOurs(line) {
            guard let original = Self.notifyArguments(line) else {
                throw Failure("Codex's notify setting is written in a way Ledge can't safely change.")
            }
            // Codex runs one notify program, so Ledge's script passes the event on to yours afterwards.
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try line.write(to: codexOriginal, atomically: true, encoding: .utf8)
            command += ["--then"] + original
        }
        backUp(codexConfig)
        let line = "notify = [" + command.map(Self.tomlString).joined(separator: ", ") + "]"
        try FileManager.default.createDirectory(at: codexConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.replacingNotifyLine(in: text, with: line).write(to: codexConfig, atomically: true, encoding: .utf8)
    }

    private func installScript() throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let body = """
        #!/bin/sh
        # Installed by Ledge: tells Ledge that a coding agent finished or is waiting on you.
        # Usage: ledge-agent <claude|codex> <done|waiting> [--then <program> <args>...]
        # Anything after --then runs afterwards with the remaining arguments (Codex adds its event JSON last).
        agent="$1"; event="$2"; shift 2
        project=$(basename "${CLAUDE_PROJECT_DIR:-$PWD}" | sed 's/%/%25/g; s/ /%20/g; s/&/%26/g; s/#/%23/g')
        open -g "ledge://agent/$agent/$event?project=$project" >/dev/null 2>&1
        if [ "$1" = "--then" ]; then shift; exec "$@"; fi
        exit 0
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }

    // MARK: File helpers

    /// The first change keeps a copy of the file as it was, next to it.
    private func backUp(_ file: URL) {
        let backup = file.appendingPathExtension("ledge-backup")
        guard FileManager.default.fileExists(atPath: file.path), !FileManager.default.fileExists(atPath: backup.path) else { return }
        try? FileManager.default.copyItem(at: file, to: backup)
    }

    private func readJSON(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func writeJSON(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    // MARK: Pure parts (tested)

    nonisolated static func claudeHooks(in settings: [String: Any]) -> [String] {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        return hooks.values.compactMap { $0 as? [[String: Any]] }.flatMap { $0 }
            .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
            .filter(isOurs)
    }

    nonisolated static func removingClaudeHooks(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let kept = entries.filter { entry in
                !((entry["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String).map(isOurs) == true }
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    /// The top-level `notify = …` line, if there is one (before any [table] header).
    nonisolated static func codexNotifyLine(in text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { return nil }
            if trimmed.hasPrefix("notify"), trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces).hasPrefix("=") { return String(line) }
        }
        return nil
    }

    nonisolated static func chainable(_ line: String) -> Bool { notifyArguments(line) != nil || isOurs(line) }

    /// The strings in a single-line `notify = ["a", "b"]`, or nil for anything else (multi-line arrays, non-strings).
    nonisolated static func notifyArguments(_ line: String) -> [String]? {
        guard let open = line.firstIndex(of: "["), let close = line.lastIndex(of: "]"), open < close else { return nil }
        let inner = line[line.index(after: open)..<close]
        var arguments: [String] = [], current = "", inString = false, escaped = false
        for character in inner {
            if inString {
                if escaped { current.append(character); escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { arguments.append(current); current = ""; inString = false }
                else { current.append(character) }
            } else if character == "\"" {
                inString = true
            } else if !(character == "," || character.isWhitespace) {
                return nil
            }
        }
        return inString ? nil : arguments
    }

    /// Swaps the top-level notify line for `line` (or removes it when nil); adds one at the top if there was none.
    nonisolated static func replacingNotifyLine(in text: String, with line: String?) -> String {
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if let existing = codexNotifyLine(in: text), let index = lines.firstIndex(of: existing) {
            if let line { lines[index] = line } else { lines.remove(at: index) }
        } else if let line {
            lines.insert(line, at: 0) // top-level keys must come before any [table]
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func tomlString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
