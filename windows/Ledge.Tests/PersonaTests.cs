using System.IO;

namespace Ledge.Tests;

public class LayoutTests
{
    [Fact]
    public void NoPersonaMeansEverythingOn() =>
        Assert.Equal(Enum.GetValues<Tool>(), Layout.Merging([]).Tools);

    [Fact]
    public void DeveloperLeadsWithAgentsThenPorts()
    {
        var layout = Layout.Merging([Persona.Developer]);
        Assert.Equal([Tool.AgentAlerts, Tool.Ports], layout.Tools.Take(2));
        Assert.Equal(Tool.Ports, layout.Tabs[0]);
    }

    [Fact]
    public void DesignerLeavesPortsAndKeepAwakeOff()
    {
        var layout = Layout.Merging([Persona.Designer]);
        Assert.DoesNotContain(Tool.Ports, layout.Tools);
        Assert.DoesNotContain(Tool.KeepAwake, layout.Tools);
        Assert.Equal([Tool.Timer], layout.Tabs);
    }

    [Fact]
    public void MergingTurnsOnWhatAnyPersonaWantsAtItsBestRank()
    {
        // Designer ranks the color picker first; Developer ranks agent alerts first. Both are rank 0, so the first pick wins the tie.
        Assert.Equal(Tool.ColorPicker, Layout.Merging([Persona.Designer, Persona.Developer]).Tools[0]);
        Assert.Equal(Tool.AgentAlerts, Layout.Merging([Persona.Developer, Persona.Designer]).Tools[0]);
        Assert.Contains(Tool.Ports, Layout.Merging([Persona.Designer, Persona.Developer]).Tools);
    }

    [Fact]
    public void FirstPickDecidesTheClosedIsland()
    {
        Assert.Equal(ClosedActivity.Media, Layout.Merging([Persona.Creator, Persona.Student]).ClosedOrder[0]);
        Assert.Equal(ClosedActivity.Timer, Layout.Merging([Persona.Student, Persona.Creator]).ClosedOrder[0]);
    }

    [Fact]
    public void EveryPersonaHasWordsAndAGlyph()
    {
        foreach (var persona in Enum.GetValues<Persona>())
        {
            Assert.False(string.IsNullOrWhiteSpace(persona.Blurb()));
            Assert.NotEmpty(persona.Ranking());
            Assert.Single(persona.Glyph());
        }
    }
}

public class SettingsTests
{
    [Fact]
    public void SwitchedOffToolsStayOff()
    {
        var settings = new Settings { Personas = [Persona.Developer], Off = [Tool.Ports] };
        Assert.False(settings.IsOn(Tool.Ports));
        Assert.True(settings.IsOn(Tool.Timer));
        Assert.False(new Settings { Personas = [Persona.Designer] }.IsOn(Tool.Ports)); // not in the persona at all
    }

    [Fact]
    public void SavesAndLoadsWithReadableNames()
    {
        var path = Path.Combine(Path.GetTempPath(), $"ledge-{Guid.NewGuid()}", "settings.json");
        try
        {
            new Settings { SetupDone = true, Personas = [Persona.Student, Persona.Developer], Off = [Tool.KeepAwake] }.Save(path);
            Assert.Contains("\"Student\"", File.ReadAllText(path));
            var loaded = Settings.Load(path);
            Assert.True(loaded.SetupDone);
            Assert.Equal([Persona.Student, Persona.Developer], loaded.Personas);
            Assert.Equal([Tool.KeepAwake], loaded.Off);
        }
        finally
        {
            Directory.Delete(Path.GetDirectoryName(path)!, recursive: true);
        }
    }

    [Fact]
    public void AMissingOrBrokenFileMeansSetUpAgain()
    {
        var path = Path.Combine(Path.GetTempPath(), $"ledge-{Guid.NewGuid()}.json");
        Assert.False(Settings.Load(path).SetupDone);
        File.WriteAllText(path, "{ not json");
        try
        {
            Assert.False(Settings.Load(path).SetupDone);
        }
        finally
        {
            File.Delete(path);
        }
    }
}
