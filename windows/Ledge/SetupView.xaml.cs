using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;

namespace Ledge;

public partial class SetupView : UserControl
{
    enum Step { Welcome, Personas, Tools, Done }

    Step step;
    readonly List<Persona> picked = [];
    readonly HashSet<Tool> off = [];

    /// <summary>Setup is finished; the settings are ready to save and apply.</summary>
    public event Action<Settings>? Finished;

    public SetupView()
    {
        InitializeComponent();
        StartAtLoginToggle.Checked += (_, _) => StartAtLoginGlyph.Text = ""; // a tick
        StartAtLoginToggle.Unchecked += (_, _) => StartAtLoginGlyph.Text = ""; // an empty box
    }

    /// <summary>Starts over, from what's saved: running setup again keeps your picks.</summary>
    public void Begin(Settings settings)
    {
        picked.Clear();
        picked.AddRange(settings.Personas);
        off.Clear();
        off.UnionWith(settings.Off);
        StartAtLoginToggle.IsChecked = settings.SetupDone ? StartAtLogin.IsOn : true;
        StartAtLoginGlyph.Text = StartAtLoginToggle.IsChecked == true ? "" : "";
        Show(settings.SetupDone ? Step.Personas : Step.Welcome);
    }

    void Show(Step next)
    {
        step = next;
        PersonaCards.Visibility = step == Step.Personas ? Visibility.Visible : Visibility.Collapsed;
        ToolChips.Visibility = step == Step.Tools ? Visibility.Visible : Visibility.Collapsed;
        StartAtLoginToggle.Visibility = step == Step.Done ? Visibility.Visible : Visibility.Collapsed;
        BackButton.Visibility = step is Step.Welcome ? Visibility.Collapsed : Visibility.Visible;
        StepText.Text = step is Step.Welcome ? "" : $"Step {(int)step} of 3";
        (Heading.Text, Subheading.Text, NextButton.Content) = step switch
        {
            Step.Welcome => ("Welcome to Ledge", "Your everyday tools, at the top of your screen. Tell it what you do and it sets itself up around you.", "Get started"),
            Step.Personas => ("What do you do?", "Pick one or more. The first one you pick decides what comes first.", "Next"),
            Step.Tools => ("Here's your Ledge", "Switch off anything you won't use. You can run setup again from Ledge's icon in the notification area.", "Next"),
            _ => ("You're all set", DoneText(), "Done"),
        };
        if (step == Step.Personas) BuildPersonaCards();
        if (step == Step.Tools) BuildToolChips();
        NextButton.IsEnabled = step != Step.Personas || picked.Count > 0;
    }

    /// <summary>How to open Ledge, plus the one extra step a couple of tools need.</summary>
    string DoneText()
    {
        var layout = Layout.Merging(picked);
        bool On(Tool tool) => layout.Tools.Contains(tool) && !off.Contains(tool);
        var text = "Rest the pointer at the top centre of your screen, or push it against the top edge, to open Ledge.";
        if (On(Tool.Calendar)) text += " Add your calendar from the Calendar tab.";
        if (On(Tool.AgentAlerts)) text += " Connect Claude Code or Codex from Ledge's icon in the notification area.";
        return text;
    }

    void Back_Click(object sender, RoutedEventArgs e) => Show(step - 1);

    void Next_Click(object sender, RoutedEventArgs e)
    {
        if (step != Step.Done)
        {
            Show(step + 1);
            return;
        }
        StartAtLogin.IsOn = StartAtLoginToggle.IsChecked == true;
        var layout = Layout.Merging(picked);
        Finished?.Invoke(new Settings { SetupDone = true, Personas = [.. picked], Off = [.. off.Where(layout.Tools.Contains)] });
    }

    void BuildPersonaCards()
    {
        PersonaCards.Children.Clear();
        foreach (var persona in Enum.GetValues<Persona>())
        {
            var order = picked.IndexOf(persona);
            var card = new ToggleButton
            {
                Style = (Style)FindResource("Toggle"),
                IsChecked = order >= 0,
                Margin = new Thickness(3),
                Padding = new Thickness(12, 8, 12, 8),
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                Content = PersonaCard(persona, order),
            };
            card.Click += (_, _) =>
            {
                if (!picked.Remove(persona)) picked.Add(persona);
                Show(Step.Personas); // renumbers the picks
            };
            PersonaCards.Children.Add(card);
        }
    }

    static UIElement PersonaCard(Persona persona, int order)
    {
        var title = new StackPanel { Orientation = Orientation.Horizontal };
        title.Children.Add(new TextBlock { Text = persona.Glyph(), Style = (Style)Application.Current.FindResource("Glyph"), Margin = new Thickness(0, 0, 8, 0) });
        title.Children.Add(new TextBlock { Text = persona.Title(), FontWeight = FontWeights.SemiBold, Foreground = Brushes.White });
        var card = new DockPanel();
        if (order >= 0)
        {
            // Numbered, because the first pick leads.
            var number = new TextBlock { Text = $"{order + 1}", FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White };
            DockPanel.SetDock(number, Dock.Right);
            card.Children.Add(number);
        }
        var text = new StackPanel();
        text.Children.Add(title);
        text.Children.Add(new TextBlock { Text = persona.Blurb(), FontSize = 11, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) });
        card.Children.Add(text);
        return card;
    }

    void BuildToolChips()
    {
        ToolChips.Children.Clear();
        foreach (var tool in Layout.Merging(picked).Tools)
        {
            var chip = new ToggleButton
            {
                Style = (Style)FindResource("Toggle"),
                IsChecked = !off.Contains(tool),
                Height = 36,
                Margin = new Thickness(0, 0, 8, 8),
                Content = ChipContent(tool),
            };
            chip.Click += (_, _) =>
            {
                if (chip.IsChecked == true) off.Remove(tool);
                else off.Add(tool);
            };
            ToolChips.Children.Add(chip);
        }
    }

    static UIElement ChipContent(Tool tool)
    {
        var content = new StackPanel { Orientation = Orientation.Horizontal };
        content.Children.Add(new TextBlock { Text = tool.Glyph(), Style = (Style)Application.Current.FindResource("Glyph"), Margin = new Thickness(0, 0, 8, 0) });
        content.Children.Add(new TextBlock { Text = tool.Name() });
        return content;
    }
}
