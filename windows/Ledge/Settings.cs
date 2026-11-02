using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ledge;

/// <summary>What you told Ledge in setup, kept in %APPDATA%\Ledge\settings.json.</summary>
public sealed class Settings
{
    public static readonly string DefaultPath =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Ledge", "settings.json");

    static readonly JsonSerializerOptions Json = new() { WriteIndented = true, Converters = { new JsonStringEnumConverter() } };

    public bool SetupDone { get; set; }
    /// <summary>In the order they were picked: the first decides ties.</summary>
    public List<Persona> Personas { get; set; } = [];
    /// <summary>Tools your personas include that you switched off in setup.</summary>
    public List<Tool> Off { get; set; } = [];
    /// <summary>Your calendar's private ICS address. It stays in this file on this PC.</summary>
    public string? CalendarLink { get; set; }

    [JsonIgnore] public Layout Layout => Layout.Merging(Personas);

    public bool IsOn(Tool tool) => Layout.Tools.Contains(tool) && !Off.Contains(tool);

    /// <summary>A missing or unreadable file means setup hasn't happened yet; it never stops Ledge starting.</summary>
    public static Settings Load(string path)
    {
        try
        {
            return JsonSerializer.Deserialize<Settings>(File.ReadAllText(path), Json) ?? new();
        }
        catch (Exception)
        {
            return new();
        }
    }

    /// <summary>Writes a new file and swaps it in, so a crash mid-save can't leave half a file behind.</summary>
    public void Save(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(this, Json));
        File.Move(temporary, path, overwrite: true);
    }
}
