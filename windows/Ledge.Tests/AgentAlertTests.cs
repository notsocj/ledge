using System.Text.Json.Nodes;

namespace Ledge.Tests;

public class AgentAlertTests
{
    const string Exe = @"C:\Users\cj\Apps\Ledge.exe";

    [Fact]
    public void ClaudeHookUsesForwardSlashesForGitBash() =>
        Assert.Equal("\"C:/Users/cj/Apps/Ledge.exe\" --agent claude done", AgentAlerts.ClaudeCommand(Exe, "done"));

    [Fact]
    public void ConnectingAddsBothHooksAndKeepsYoursAndOtherSettings()
    {
        var settings = JsonNode.Parse("""
            { "model": "opus", "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "say done" } ] } ] } }
            """)!.AsObject();
        var connected = AgentAlerts.AddingClaudeHooks(settings, Exe);
        Assert.Equal("opus", (string?)connected["model"]);
        Assert.Equal(2, AgentAlerts.ClaudeHooks(connected).Count);
        Assert.Equal(2, connected["hooks"]!["Stop"]!.AsArray().Count); // yours, then Ledge's

        var twice = AgentAlerts.AddingClaudeHooks(connected, Exe);
        Assert.Equal(2, AgentAlerts.ClaudeHooks(twice).Count); // reconnecting replaces, never duplicates

        var disconnected = AgentAlerts.RemovingClaudeHooks(twice);
        Assert.Empty(AgentAlerts.ClaudeHooks(disconnected));
        Assert.Equal("say done", (string?)disconnected["hooks"]!["Stop"]![0]!["hooks"]![0]!["command"]);
        Assert.Null(disconnected["hooks"]!["Notification"]); // emptied events are removed
    }

    [Fact]
    public void DisconnectingFromOnlyLedgeRemovesTheHooksKey()
    {
        var connected = AgentAlerts.AddingClaudeHooks(new JsonObject(), Exe);
        Assert.Null(AgentAlerts.RemovingClaudeHooks(connected)["hooks"]);
    }

    [Theory]
    [InlineData("notify = [\"a\", \"b c\"]", new[] { "a", "b c" })]
    [InlineData("notify = [ \"C:\\\\tools\\\\ping.exe\" ]", new[] { "C:\\tools\\ping.exe" })]
    [InlineData("notify = []", new string[0])]
    public void ReadsCodexNotifyArguments(string line, string[] expected) =>
        Assert.Equal(expected, AgentAlerts.NotifyArguments(line));

    [Theory]
    [InlineData("notify = [\"a\",")] // multi-line array
    [InlineData("notify = [1, 2]")] // not strings
    [InlineData("notify = \"a\"")]
    public void RefusesNotifyLinesItCannotSafelyRewrite(string line) => Assert.Null(AgentAlerts.NotifyArguments(line));

    [Fact]
    public void FindsOnlyTheTopLevelNotifyLine()
    {
        Assert.Equal("notify = [\"x\"]", AgentAlerts.CodexNotifyLine("model = \"o3\"\nnotify = [\"x\"]\n[tools]\nnotify = [\"y\"]"));
        Assert.Null(AgentAlerts.CodexNotifyLine("[tools]\nnotify = [\"y\"]"));
    }

    [Fact]
    public void ReplacesAddsAndRemovesTheNotifyLine()
    {
        var line = AgentAlerts.NotifyLine([Exe, "--agent", "codex", "done"]);
        Assert.Equal("notify = [\"C:\\\\Users\\\\cj\\\\Apps\\\\Ledge.exe\", \"--agent\", \"codex\", \"done\"]", line);
        Assert.Equal(line + "\n[tools]", AgentAlerts.ReplacingNotifyLine("[tools]", line)); // added above any table
        Assert.Equal("a = 1\n" + line, AgentAlerts.ReplacingNotifyLine("a = 1\nnotify = [\"old\"]", line));
        Assert.Equal("a = 1", AgentAlerts.ReplacingNotifyLine("a = 1\nnotify = [\"old\"]", null));
        Assert.True(AgentAlerts.IsOurs(line));
        Assert.False(AgentAlerts.IsOurs("notify = [\"notify-send\"]"));
    }
}
