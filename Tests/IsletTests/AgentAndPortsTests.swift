import Foundation
import Testing
@testable import Islet

@Test func readsCodexNotifyOnlyAtTheTopLevel() {
    let config = """
    model = "gpt-5"
    notify = ["/Applications/Helper.app/Contents/MacOS/helper", "turn-ended"]

    [profiles.work]
    notify = ["ignored"]
    """
    let line = AgentAlerts.codexNotifyLine(in: config)
    #expect(line == #"notify = ["/Applications/Helper.app/Contents/MacOS/helper", "turn-ended"]"#)
    #expect(AgentAlerts.notifyArguments(line!) == ["/Applications/Helper.app/Contents/MacOS/helper", "turn-ended"])
    #expect(AgentAlerts.codexNotifyLine(in: "[tui]\nnotify = [\"x\"]") == nil) // inside a table, not top level
}

@Test func refusesNotifyValuesItCannotRewriteSafely() {
    #expect(AgentAlerts.notifyArguments(#"notify = ["a", 3]"#) == nil)          // not all strings
    #expect(AgentAlerts.notifyArguments(#"notify = ["unterminated]"#) == nil)
    #expect(AgentAlerts.notifyArguments(#"notify = ["say \"hi\"", "b"]"#) == [#"say "hi""#, "b"])
}

@Test func swapsOrAddsTheNotifyLineWithoutTouchingTheRest() {
    let config = "model = \"gpt-5\"\nnotify = [\"old\"]\n\n[tui]\ntheme = \"dark\""
    let ours = #"notify = ["/path/islet-agent", "codex", "done", "--then", "old"]"#
    #expect(AgentAlerts.replacingNotifyLine(in: config, with: ours) == "model = \"gpt-5\"\n\(ours)\n\n[tui]\ntheme = \"dark\"")
    #expect(AgentAlerts.replacingNotifyLine(in: config, with: nil) == "model = \"gpt-5\"\n\n[tui]\ntheme = \"dark\"")
    // No notify yet: it goes first, so it can't land inside a [table].
    #expect(AgentAlerts.replacingNotifyLine(in: "[tui]\ntheme = \"dark\"", with: ours) == "\(ours)\n[tui]\ntheme = \"dark\"")
    #expect(AgentAlerts.tomlString(#"C:\a "b""#) == #""C:\\a \"b\"""#)
}

@Test func addsAndRemovesOnlyIsletsClaudeHooks() {
    let theirs: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]], "theme": "dark"]
    var settings = theirs
    var hooks = settings["hooks"] as! [String: Any]
    var stop = hooks["Stop"] as! [[String: Any]]
    stop.append(["hooks": [["type": "command", "command": "\"/x/islet-agent\" claude done"]]])
    hooks["Stop"] = stop
    hooks["Notification"] = [["hooks": [["type": "command", "command": "\"/x/islet-agent\" claude waiting"]]]]
    settings["hooks"] = hooks
    #expect(AgentAlerts.claudeHooks(in: settings).count == 2)

    let cleaned = AgentAlerts.removingClaudeHooks(from: settings)
    #expect(AgentAlerts.claudeHooks(in: cleaned).isEmpty)
    #expect(NSDictionary(dictionary: cleaned) == NSDictionary(dictionary: theirs)) // the user's own hook and settings survive
}

@Test func parsesListeningPortsOncePerPort() {
    let output = "p100\ncnode\nf20\nn*:3000\nf21\nn[::1]:3000\np200\ncpython3\nf5\nn127.0.0.1:8000\np300\ncSpotify\nf9\nn*:57621\n"
    #expect(Ports.parse(output) == [
        Ports.Listener(port: 3000, pid: 100, command: "node"),
        Ports.Listener(port: 8000, pid: 200, command: "python3"),
    ]) // 57621 is in the private range apps use internally
}
