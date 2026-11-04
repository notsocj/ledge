# Ledge for Windows

The Windows version of Ledge. Windows laptops have no notch, so the island floats as a pill at the top
centre of the screen. Rest the pointer on it, push the pointer against the top edge above it, or tap it
to open it. Ledge's icon in the notification area has the menu: a test alert, coding agent alerts,
start at sign-in, **Change what Ledge shows…** and Quit.

## Install

Download `Ledge-win-Setup.exe` from the newest
[Windows release](https://github.com/notsocj/ledge/releases) (or from [the website](https://keepledge.vercel.app),
which offers it to visitors on Windows) and run it. It installs for you only (no admin rights) into
`%LOCALAPPDATA%\Ledge` and adds Ledge to the Start menu.

It keeps itself up to date from GitHub: a new version downloads quietly and goes in when Ledge quits,
or straight away from **Restart to update** in the notification-area menu. Uninstall from Settings >
Apps; that also removes the sign-in entry and any coding agent hooks.

The installer isn't code-signed yet, so Windows may show "Windows protected your PC": choose
**More info**, then **Run anyway**. Ledge needs Windows 10 (2004) or later, on x64 or Arm64 (Arm64 runs
the x64 installer emulated for now).

## Setup

The first time it runs, setup opens inside the island: pick what you do (Developer, Designer, Creator,
Student, Professional or Essentials, as many as fit) and Ledge switches on the tools for it and puts the
most important first. The first one you pick leads; picks are numbered so you can see the order. Switch
off anything you won't use, then choose whether it starts when you sign in. Your choices are saved in
`%APPDATA%\Ledge\settings.json`; run setup again from the notification-area icon.

## Tabs

Open, the island's tabs sit on both sides of its top edge, as the Mac's sit on both sides of the
notch: Home and the first half of your tabs on the left, the rest on the right. The open tab shows its
icon and name; the others are icons (point at one for its name). Switching slides the highlight across
to the new tab and opens its name. With Windows' **Animation effects** off, it moves without sliding.

- **Home**: what's playing (previous, play/pause, next), your next meeting, the battery and Keep awake.
  Music has larger artwork, a two-line title and controls aligned to the artwork's bottom edge, with
  a 24-point gap before the status cards. When those cards are hidden, the player uses the full row.
- **Calendar**: today's and tomorrow's meetings with Join buttons for Teams, Zoom, Meet and Webex links.
  Windows has no calendar API like the Mac's, so Ledge reads your calendar's private ICS link: copy it
  from Outlook (Publish a calendar) or Google Calendar (Secret address in iCal format) and press
  **Paste calendar link**. It refreshes every 15 minutes and the link stays in your settings file.
- **Timer**: 5, 15 or 25 minutes, with pause, +1 min and cancel. It counts down in the closed island too.
- **Ports**: dev servers listening on localhost, with Open in browser and Stop (click twice).
- **Clipboard**: the last 20 things you copied as text, in memory only. Copies that password managers
  mark as private are never kept.
- **Shelf**: drag files onto the island to keep them handy, then drag them out again. Nothing is copied.
- **Color**: pick a color from anywhere on screen; its hex code is copied.

## Alerts

The compact island grows to hold an alert when you plug in, when the battery drops to 20% and 10%, when a
timer ends, two minutes before a meeting, when an app turns on the microphone or camera, and when Claude
Code or Codex finishes or needs you. A circular badge, two lines of context and a colored status keep
each alert readable. The same black surface gently grows and settles on entry, then returns to its
compact size on exit; the text stays steady inside it. Replacing an alert retargets that same surface,
even during dismissal. The compact area remains the hover trigger, so an alert expanding underneath
the pointer never opens Home by itself. With Windows' **Animation effects** off, the size changes
immediately and the content fades. Color-picker feedback is immediate.

Alerts that need attention (an agent waiting, a meeting or a finished timer) take priority over routine
status. Repeated alerts from the same source are grouped, and an agent finishing replaces its older
waiting message. Home and full-screen apps hold a small queue of up to four fresh alerts. Old alerts
expire instead of replaying when you return; identical repeats do not keep an alert on screen forever.
Immediate color feedback is never queued.

**Coding agent alerts** are connected from the notification-area icon (**Coding agent alerts**). Ledge
adds two hooks to `~/.claude/settings.json` and a `notify` line to `~/.codex/config.toml`, each running
`Ledge.exe --agent …`; both files are backed up first (`.ledge-backup`), an existing Codex notify program
keeps running after Ledge's, and disconnecting removes only what Ledge added. If you move `Ledge.exe`,
the hooks follow it the next time it starts.

## Build it yourself

Needs Windows 10 (2004) or later and the [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0).
From the repository root:

```powershell
dotnet run --project windows/Ledge
dotnet test windows/Ledge.Tests
```

The project also compiles on macOS and Linux (`EnableWindowsTargeting`), which catches XAML and C#
errors, but it only runs on Windows. A copy run straight from a build never updates itself.

### Snapshots

To review the design without clicking through it, or without a Windows PC to hand:

```powershell
dotnet run --project windows/Ledge -- --snapshot snapshots
```

renders the open island on every tab and each setup step to PNGs at 200%, with made-up music, meetings,
servers, clipboard and files, and quits. It never reads or changes your settings.

It also captures long-title, empty and solo Home layouts, notification samples and motion contact sheets.
For native 30 fps notification frames, including interrupted dismissal and reduced motion:

```powershell
dotnet run --project windows/Ledge -- --notification-preview notifications
```

This isolated notification preview uses the production component without starting services or reading
personal data. CI includes the numbered frames in its `Ledge-snapshots` artifact.

Every push that touches `windows/` is built on GitHub Actions for x64 and Arm64 (the
[Windows workflow](../.github/workflows/windows.yml)): it runs the tests, attaches the builds and the
installer to the run, renders the snapshots, uploads them as the `Ledge-snapshots` artifact, and also
pushes them to the `windows-snapshots` branch (replaced each run), so they can be viewed with plain git:

```bash
git fetch origin windows-snapshots && git archive FETCH_HEAD | tar -x -C snapshots
```

## Design

The island is pure black with white text at a few fixed strengths, as on the Mac. Text is
[Poppins](https://github.com/itfoundry/Poppins), bundled in `Ledge/Assets/Fonts`, and weight carries the
hierarchy (the type scale is in `App.xaml`):

| Style | Size, weight | For |
|---|---|---|
| Display | 40, Bold | the countdown |
| Heading | 18, Bold | setup's headings |
| Title | 14, SemiBold | the song, an empty page's title, the battery, a port |
| Headline | 13, SemiBold | an alert's title, a meeting, a persona |
| Row | 12.5, Medium | tabs, buttons, list rows |
| Body | 12.5, Regular | supporting text: the artist, a process name, explanations |
| Label | 11.5, Medium | small names over a value or group: Battery, Today |
| Caption | 11.5, Regular | small hints beside a page's controls |

Poppins has no fixed-width digits, so numbers that tick (the countdown in the Timer tab and the closed
island) use `TabularText`, which gives every digit the same width. Icons are Segoe Fluent Icons, which
come with Windows.

## Layout

```
windows/
  Ledge/
    App.xaml(.cs)          entry point, installer hooks, colors, type scale and control styles
    IslandWindow.xaml(.cs) the island window: shape, spring motion, hover, alerts, closed states
    OpenPanel.xaml(.cs)    the open island: two-sided tabs, Home, Timer, Ports
    SetupView.xaml(.cs)    first-run setup inside the island
    CalendarPage, ClipboardPage, ColorPage, ShelfPage   the other tabs
    Persona.cs             personas, tools and how they merge into a layout
    Settings.cs            what setup saved, in %APPDATA%\Ledge\settings.json
    TabularText.cs         text with fixed-width digits
    Snapshots.cs           --snapshot
    Spring.cs, HoverIntent.cs, Native.cs, Tray.cs, Updates.cs, StartAtLogin.cs
    IslandSurface, IslandMotion   one shape that morphs between compact, notification and open states
    NotificationCapsule, NotificationContent, NotificationMotion   alert content and reveal timing
    Tools/                 one file per tool
    Assets/                the app icon and the Poppins font files
  Ledge.Tests/
```

## Releasing

Bump `<Version>` in `Ledge/Ledge.csproj`, then push a tag named `windows-v` and the version, for example
`windows-v0.1.1`. The [Windows release workflow](../.github/workflows/windows-release.yml) runs the
tests, builds the installer with [Velopack](https://velopack.io) and publishes a GitHub release with it.
Windows releases are never marked latest, so the Mac download links and the Homebrew tap keep pointing
at the Mac release. The website finds the newest `windows-v` release on its own and offers it to
visitors on Windows; its fallback links (used only if GitHub can't be reached) name a version in
`site/index.html`, so move them to the new release once it's published.

## Credits

- Font: [Poppins](https://github.com/itfoundry/Poppins) by the Poppins Project Authors, SIL Open Font
  License 1.1 (`Ledge/Assets/Fonts/OFL.txt`).
- Calendar links: [Ical.Net](https://github.com/rianjs/ical.net), MIT.
- Installer and updates: [Velopack](https://velopack.io), MIT.
