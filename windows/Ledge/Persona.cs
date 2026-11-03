namespace Ledge;

/// <summary>Tools you can switch off. Home and the battery alerts are always there.</summary>
public enum Tool { Media, Timer, Ports, KeepAwake, AgentAlerts, Clipboard, Shelf, ColorPicker, InUse, Calendar }

/// <summary>What shows beside the closed island when more than one thing is live.</summary>
public enum ClosedActivity { Timer, Media }

/// <summary>What someone does. Each persona is a ranked list of tools, which decides what's on, the tab
/// order, and what wins the closed island. Its description only names tools Windows has today.</summary>
public enum Persona { Developer, Designer, Creator, Student, Professional, Essentials }

public static class Personas
{
    public static string Title(this Persona persona) => persona.ToString();

    public static string Blurb(this Persona persona) => persona switch
    {
        Persona.Developer => "Agent alerts, localhost ports and the clipboard.",
        Persona.Designer => "A color picker, a shelf for assets and the clipboard.",
        Persona.Creator => "Music, timers, a shelf for clips and what's using your mic.",
        Persona.Student => "Timers, your class calendar and music.",
        Persona.Professional => "Meetings, what's using your mic and camera, and the clipboard.",
        _ => "Music, shelf, clipboard and calendar. Nothing more.",
    };

    /// <summary>Segoe Fluent Icons glyphs.</summary>
    public static string Glyph(this Persona persona) => persona switch
    {
        Persona.Developer => "",
        Persona.Designer => "",
        Persona.Creator => "",
        Persona.Student => "",
        Persona.Professional => "",
        _ => "",
    };

    /// <summary>Most important first. Tools left out are off for this persona.</summary>
    public static Tool[] Ranking(this Persona persona) => persona switch
    {
        Persona.Developer => [Tool.AgentAlerts, Tool.Ports, Tool.Clipboard, Tool.Shelf, Tool.Calendar, Tool.Media, Tool.Timer, Tool.KeepAwake],
        Persona.Designer => [Tool.ColorPicker, Tool.Shelf, Tool.Clipboard, Tool.Media, Tool.Calendar, Tool.Timer],
        Persona.Creator => [Tool.Media, Tool.Timer, Tool.Shelf, Tool.KeepAwake, Tool.InUse],
        Persona.Student => [Tool.Timer, Tool.Calendar, Tool.Media, Tool.Clipboard, Tool.KeepAwake],
        Persona.Professional => [Tool.Calendar, Tool.InUse, Tool.Clipboard, Tool.Timer, Tool.Shelf, Tool.Media, Tool.KeepAwake],
        _ => [Tool.Media, Tool.Shelf, Tool.Clipboard, Tool.Calendar, Tool.KeepAwake, Tool.Timer],
    };

    public static ClosedActivity[] ClosedOrder(this Persona persona) =>
        persona is Persona.Creator or Persona.Essentials ? [ClosedActivity.Media, ClosedActivity.Timer] : [ClosedActivity.Timer, ClosedActivity.Media];

    public static string Name(this Tool tool) => tool switch
    {
        Tool.Media => "Now playing",
        Tool.Timer => "Timer",
        Tool.Ports => "Ports",
        Tool.KeepAwake => "Keep awake",
        Tool.AgentAlerts => "Agent alerts",
        Tool.Clipboard => "Clipboard",
        Tool.Shelf => "Shelf",
        Tool.ColorPicker => "Color picker",
        Tool.InUse => "Mic and camera",
        _ => "Calendar",
    };

    public static string Glyph(this Tool tool) => tool switch
    {
        Tool.Media => "",
        Tool.Timer => "",
        Tool.Ports => "",
        Tool.KeepAwake => "",
        Tool.AgentAlerts => "",
        Tool.Clipboard => "",
        Tool.Shelf => "",
        Tool.ColorPicker => "",
        Tool.InUse => "",
        _ => "",
    };
}

/// <summary>Everything the island's arrangement depends on, worked out from the chosen personas.</summary>
public sealed record Layout(IReadOnlyList<Tool> Tools, IReadOnlyList<Tool> Tabs, IReadOnlyList<ClosedActivity> ClosedOrder)
{
    /// <summary>Tools that get a tab of their own next to Home.</summary>
    public static readonly Tool[] TabTools = [Tool.Calendar, Tool.Timer, Tool.Ports, Tool.Clipboard, Tool.Shelf, Tool.ColorPicker];

    /// <summary>Before anyone picks a persona: everything on.</summary>
    public static readonly Layout Standard = new(Enum.GetValues<Tool>(), TabTools, [ClosedActivity.Timer, ClosedActivity.Media]);

    /// <summary>Several personas merge: a tool is on if any of them wants it, and ranks as high as the
    /// persona that cares most about it. The first persona picked breaks ties and decides the closed island.</summary>
    public static Layout Merging(IReadOnlyList<Persona> personas)
    {
        if (personas.Count == 0) return Standard;
        var rankings = personas.Select(persona => persona.Ranking()).ToList();
        int Rank(Tool tool, IEnumerable<Tool[]> lists) => lists.Select(list => Array.IndexOf(list, tool)).Where(i => i >= 0).DefaultIfEmpty(int.MaxValue).Min();
        IReadOnlyList<Tool> Ordered(IEnumerable<Tool> tools) =>
            [.. tools.OrderBy(tool => Rank(tool, rankings)).ThenBy(tool => Rank(tool, rankings.Take(1))).ThenBy(tool => tool)];

        var on = Ordered(Enum.GetValues<Tool>().Where(tool => rankings.Any(list => list.Contains(tool))));
        return new(on, [.. on.Where(TabTools.Contains)], personas[0].ClosedOrder());
    }
}
