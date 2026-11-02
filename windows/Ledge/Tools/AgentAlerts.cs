using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows.Threading;

namespace Ledge;

/// <summary>
/// Lights up the island when Claude Code or Codex finishes, or is waiting on you.
///
/// Connecting points each agent at Ledge itself: Claude Code through two hooks in ~/.claude/settings.json,
/// Codex through `notify` in ~/.codex/config.toml. Each runs `Ledge.exe --agent &lt;agent&gt; &lt;event&gt;`, which
/// hands the event to the running Ledge over a named pipe and exits. Both files get a backup next to
/// them before the first change, and disconnecting undoes it.
/// </summary>
public sealed class AgentAlerts
{
    public enum Agent { Claude, Codex }
    public enum Status { NotInstalled, Disconnected, Connected, Blocked }

    static readonly string Home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    static string ClaudeFolder => Path.Combine(Home, ".claude");
    static string ClaudeSettings => Path.Combine(ClaudeFolder, "settings.json");
    static string CodexFolder => Path.Combine(Home, ".codex");
    static string CodexConfig => Path.Combine(CodexFolder, "config.toml");
    static string CodexOriginal =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Ledge", "codex-notify-original.txt");
    static string PipeName => $"Ledge.Agent.{Environment.UserName}";
    static readonly JsonSerializerOptions Indented = new() { WriteIndented = true };

    readonly string exe = Environment.ProcessPath ?? "Ledge.exe";

    public Status Claude { get; private set; }
    public Status Codex { get; private set; }
    public string? LastError { get; private set; }

    /// <summary>An agent finished (waiting false) or needs you (waiting true), in a project folder.</summary>
    public event Action<Agent, bool, string>? Event;

    public void Refresh()
    {
        Claude = !Directory.Exists(ClaudeFolder) ? Status.NotInstalled
            : ClaudeHooks(ReadJson(ClaudeSettings) ?? new JsonObject()).Count > 0 ? Status.Connected : Status.Disconnected;
        if (!Directory.Exists(CodexFolder))
        {
            Codex = Status.NotInstalled;
            return;
        }
        var line = CodexNotifyLine(ReadText(CodexConfig));
        Codex = line is null ? Status.Disconnected
            : IsOurs(line) ? Status.Connected
            : NotifyArguments(line) is null ? Status.Blocked
            : Status.Disconnected;
    }

    public void Connect(Agent agent) => Change(() =>
    {
        if (agent == Agent.Claude) ConnectClaude();
        else ConnectCodex();
    });

    public void Disconnect(Agent agent) => Change(() =>
    {
        if (agent == Agent.Claude)
        {
            if (ReadJson(ClaudeSettings) is { } settings) WriteJson(RemovingClaudeHooks(settings), ClaudeSettings);
            return;
        }
        var original = File.Exists(CodexOriginal) ? File.ReadAllText(CodexOriginal) : null;
        WriteText(ReplacingNotifyLine(ReadText(CodexConfig), string.IsNullOrEmpty(original) ? null : original), CodexConfig);
        File.Delete(CodexOriginal);
    });

    /// <summary>Ledge is a single .exe you can move; if it moved, the hooks follow it.</summary>
    public void FollowIfMoved()
    {
        Refresh();
        if (Claude == Status.Connected && ClaudeHooks(ReadJson(ClaudeSettings) ?? new JsonObject()).Any(command => !command.Contains(ForwardSlashes(exe), StringComparison.OrdinalIgnoreCase)))
            Change(ConnectClaude);
        if (Codex == Status.Connected && CodexNotifyLine(ReadText(CodexConfig)) is { } line && NotifyArguments(line) is [var oldExe, .. var rest] && oldExe != exe)
            Change(() => WriteText(ReplacingNotifyLine(ReadText(CodexConfig), NotifyLine([exe, .. rest])), CodexConfig));
    }

    void Change(Action change)
    {
        LastError = null;
        try
        {
            change();
        }
        catch (Exception error)
        {
            LastError = error.Message;
        }
        Refresh();
    }

    void ConnectClaude()
    {
        if (File.Exists(ClaudeSettings) && ReadJson(ClaudeSettings) is null)
            throw new InvalidOperationException("~/.claude/settings.json isn't valid JSON, so Ledge didn't change it.");
        BackUp(ClaudeSettings);
        WriteJson(AddingClaudeHooks(ReadJson(ClaudeSettings) ?? new JsonObject(), exe), ClaudeSettings);
    }

    void ConnectCodex()
    {
        var text = ReadText(CodexConfig);
        List<string> command = [exe, "--agent", "codex", "done"];
        if (CodexNotifyLine(text) is { } line && !IsOurs(line))
        {
            // Codex runs one notify program, so Ledge passes the event on to yours afterwards.
            var original = NotifyArguments(line) ?? throw new InvalidOperationException("Codex's notify setting is written in a way Ledge can't safely change.");
            Directory.CreateDirectory(Path.GetDirectoryName(CodexOriginal)!);
            File.WriteAllText(CodexOriginal, line);
            command.AddRange(["--then", .. original]);
        }
        BackUp(CodexConfig);
        WriteText(ReplacingNotifyLine(text, NotifyLine(command)), CodexConfig);
    }

    // Passing events from the hook to the running Ledge

    /// <summary>Runs in the short-lived copy of Ledge that an agent starts: tells the running Ledge, then
    /// starts the notify program Codex had before, if any. Never shows anything or fails loudly.</summary>
    public static void Forward(string[] args)
    {
        if (args.Length < 3) return;
        var folder = Environment.GetEnvironmentVariable("CLAUDE_PROJECT_DIR") ?? Environment.CurrentDirectory;
        var project = Path.GetFileName(folder.TrimEnd('\\', '/'));
        try
        {
            using var pipe = new NamedPipeClientStream(".", PipeName, PipeDirection.Out);
            pipe.Connect(300);
            pipe.Write(Encoding.UTF8.GetBytes($"{args[1]}\t{args[2]}\t{project}\n"));
        }
        catch (Exception)
        {
            // Ledge isn't running.
        }
        var then = Array.IndexOf(args, "--then");
        if (then < 0 || then + 1 >= args.Length) return;
        try
        {
            var start = new ProcessStartInfo(args[then + 1]) { UseShellExecute = false };
            foreach (var argument in args[(then + 2)..]) start.ArgumentList.Add(argument);
            Process.Start(start)?.Dispose();
        }
        catch (Exception)
        {
            // Their program is gone; nothing to pass on to.
        }
    }

    /// <summary>Waits for events from hooks for as long as Ledge runs.</summary>
    public async Task ListenAsync(Dispatcher dispatcher)
    {
        while (true)
        {
            try
            {
                using var server = new NamedPipeServerStream(PipeName, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
                await server.WaitForConnectionAsync();
                using var reader = new StreamReader(server, Encoding.UTF8);
                if (await reader.ReadLineAsync() is { } line && line.Split('\t') is [var agent, var kind, var project])
                {
                    var which = agent == "codex" ? Agent.Codex : Agent.Claude;
                    dispatcher.BeginInvoke(new Action(() => Event?.Invoke(which, kind == "waiting", project)));
                }
            }
            catch (Exception)
            {
                await Task.Delay(1000); // another Ledge holds the pipe, or it broke: try again shortly
            }
        }
    }

    // Pure parts (tested)

    /// <summary>Claude Code runs hooks through Git Bash, where forward slashes are the safe path separator.</summary>
    public static string ClaudeCommand(string exe, string kind) => $"\"{ForwardSlashes(exe)}\" --agent claude {kind}";

    static string ForwardSlashes(string path) => path.Replace('\\', '/');

    public static bool IsOurs(string command) =>
        command.Contains("--agent", StringComparison.Ordinal) && command.Contains("ledge", StringComparison.OrdinalIgnoreCase);

    public static List<string> ClaudeHooks(JsonObject settings) =>
        [.. Entries(settings).SelectMany(Commands).Where(IsOurs)];

    public static JsonObject AddingClaudeHooks(JsonObject settings, string exe)
    {
        var result = RemovingClaudeHooks(settings);
        if (result["hooks"] is not JsonObject hooks)
        {
            hooks = new JsonObject();
            result["hooks"] = hooks;
        }
        // Stop: Claude finished its turn. Notification: it's asking for permission or waiting on you.
        foreach (var (kind, name) in new[] { ("Stop", "done"), ("Notification", "waiting") })
        {
            if (hooks[kind] is not JsonArray entries)
            {
                entries = new JsonArray();
                hooks[kind] = entries;
            }
            entries.Add(new JsonObject { ["hooks"] = new JsonArray(new JsonObject { ["type"] = "command", ["command"] = ClaudeCommand(exe, name) }) });
        }
        return result;
    }

    public static JsonObject RemovingClaudeHooks(JsonObject settings)
    {
        var result = settings.DeepClone().AsObject();
        if (result["hooks"] is not JsonObject hooks) return result;
        foreach (var kind in hooks.Select(pair => pair.Key).ToList())
        {
            if (hooks[kind] is not JsonArray entries) continue;
            foreach (var entry in entries.OfType<JsonObject>().Where(entry => Commands(entry).Any(IsOurs)).ToList()) entries.Remove(entry);
            if (entries.Count == 0) hooks.Remove(kind);
        }
        if (hooks.Count == 0) result.Remove("hooks");
        return result;
    }

    /// <summary>Every hook entry under every event: {"hooks": {"Stop": [entry, …], …}}.</summary>
    static IEnumerable<JsonObject> Entries(JsonObject settings) =>
        (settings["hooks"] as JsonObject)?.Select(pair => pair.Value).OfType<JsonArray>().SelectMany(entries => entries.OfType<JsonObject>()) ?? Enumerable.Empty<JsonObject>();

    /// <summary>The commands in one entry: {"hooks": [{"type": "command", "command": "…"}]}.</summary>
    static IEnumerable<string> Commands(JsonObject entry) =>
        (entry["hooks"] as JsonArray)?.OfType<JsonObject>()
            .Select(hook => hook["command"] is JsonValue value && value.GetValueKind() == JsonValueKind.String ? value.GetValue<string>() : null)
            .OfType<string>() ?? Enumerable.Empty<string>();

    /// <summary>The top-level `notify = …` line, if there is one (before any [table] header).</summary>
    public static string? CodexNotifyLine(string text)
    {
        foreach (var line in text.Split('\n'))
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith('[')) return null;
            if (trimmed.StartsWith("notify", StringComparison.Ordinal) && trimmed[6..].TrimStart().StartsWith('=')) return line;
        }
        return null;
    }

    /// <summary>The strings in a single-line `notify = ["a", "b"]`, or null for anything else (multi-line arrays, non-strings).</summary>
    public static List<string>? NotifyArguments(string line)
    {
        int open = line.IndexOf('['), close = line.LastIndexOf(']');
        if (open < 0 || close <= open) return null;
        List<string> arguments = [];
        var current = new StringBuilder();
        bool inString = false, escaped = false;
        foreach (var character in line[(open + 1)..close])
        {
            if (inString)
            {
                if (escaped) { current.Append(character); escaped = false; }
                else if (character == '\\') escaped = true;
                else if (character == '"') { arguments.Add(current.ToString()); current.Clear(); inString = false; }
                else current.Append(character);
            }
            else if (character == '"') inString = true;
            else if (character != ',' && !char.IsWhiteSpace(character)) return null;
        }
        return inString ? null : arguments;
    }

    /// <summary>Swaps the top-level notify line for `line` (or removes it when null); adds one at the top if there was none.</summary>
    public static string ReplacingNotifyLine(string text, string? line)
    {
        var lines = text.Length == 0 ? new List<string>() : text.Split('\n').ToList();
        var existing = CodexNotifyLine(text);
        var index = existing is null ? -1 : lines.IndexOf(existing);
        if (index >= 0)
        {
            if (line is null) lines.RemoveAt(index);
            else lines[index] = line;
        }
        else if (line is not null)
        {
            lines.Insert(0, line); // top-level keys must come before any [table]
        }
        return string.Join('\n', lines);
    }

    public static string NotifyLine(IEnumerable<string> command) => "notify = [" + string.Join(", ", command.Select(TomlString)) + "]";

    public static string TomlString(string value) => "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";

    // Files

    /// <summary>The first change keeps a copy of the file as it was, next to it.</summary>
    static void BackUp(string file)
    {
        var backup = file + ".ledge-backup";
        if (File.Exists(file) && !File.Exists(backup)) File.Copy(file, backup);
    }

    static JsonObject? ReadJson(string path)
    {
        if (!File.Exists(path)) return new JsonObject();
        try
        {
            return JsonNode.Parse(File.ReadAllText(path)) as JsonObject;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    static void WriteJson(JsonObject json, string path) => WriteText(json.ToJsonString(Indented), path);

    static string ReadText(string path) => File.Exists(path) ? File.ReadAllText(path) : "";

    static void WriteText(string text, string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".ledge-tmp";
        File.WriteAllText(temporary, text);
        File.Move(temporary, path, overwrite: true);
    }
}
