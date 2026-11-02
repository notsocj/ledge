namespace Ledge;

/// <summary>Tools you can switch off. Home and the battery alerts are always there.</summary>
public enum Tool { Media, Timer, Ports, KeepAwake }

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
        Persona.Developer => "Localhost ports, keep awake and a timer.",
        Persona.Designer => "Your music while you work, and a timer.",
        Persona.Creator => "Music first, a timer, and keep awake for long renders.",
        Persona.Student => "A study timer, your music and keep awake.",
        Persona.Professional => "A timer for calls and keep awake for presentations.",
        _ => "Music and a timer. Nothing more.",
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
        Persona.Developer => [Tool.Ports, Tool.KeepAwake, Tool.Timer, Tool.Media],
        Persona.Designer => [Tool.Media, Tool.Timer],
        Persona.Creator => [Tool.Media, Tool.Timer, Tool.KeepAwake],
        Persona.Student => [Tool.Timer, Tool.Media, Tool.KeepAwake],
        Persona.Professional => [Tool.Timer, Tool.KeepAwake, Tool.Media],
        _ => [Tool.Media, Tool.Timer],
    };

    public static ClosedActivity[] ClosedOrder(this Persona persona) =>
        persona is Persona.Creator or Persona.Essentials ? [ClosedActivity.Media, ClosedActivity.Timer] : [ClosedActivity.Timer, ClosedActivity.Media];

    public static string Name(this Tool tool) => tool switch
    {
        Tool.Media => "Now playing",
        Tool.Timer => "Timer",
        Tool.Ports => "Ports",
        _ => "Keep awake",
    };

    public static string Glyph(this Tool tool) => tool switch
    {
        Tool.Media => "",
        Tool.Timer => "",
        Tool.Ports => "",
        _ => "",
    };
}

/// <summary>Everything the island's arrangement depends on, worked out from the chosen personas.</summary>
public sealed record Layout(IReadOnlyList<Tool> Tools, IReadOnlyList<Tool> Tabs, IReadOnlyList<ClosedActivity> ClosedOrder)
{
    /// <summary>Tools that get a tab of their own next to Home.</summary>
    public static readonly Tool[] TabTools = [Tool.Timer, Tool.Ports];

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
