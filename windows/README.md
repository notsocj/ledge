# Ledge for Windows

Download `Ledge-win-Setup.exe` from the newest
[Windows release](https://github.com/notsocj/ledge/releases) and run it. It installs for you only (no
admin rights) into `%LOCALAPPDATA%\Ledge`, adds Ledge to the Start menu, and keeps itself up to date
from GitHub: a new version downloads quietly and goes in when Ledge quits, or straight away from
**Restart to update** in the notification-area menu. Uninstall from Settings > Apps; that also removes
the sign-in entry and any coding agent hooks. The installer isn't code-signed yet, so Windows may show
"Windows protected your PC": choose **More info**, then **Run anyway**.

The Windows version of Ledge. Windows laptops have no notch, so the island floats as a pill
at the top centre of the screen. Rest the pointer on it, push the pointer against the top edge above it,
or tap it to open it. Ledge's icon in the notification area has the menu: a test alert, start at sign-in,
and Quit.

The first time it runs, setup opens inside the island: pick what you do (Developer, Designer, Creator,
Student, Professional or Essentials, as many as fit) and Ledge switches on the tools for it and puts the
most important first. Switch off anything you won't use, then choose whether it starts when you sign in.
Your choices are saved in `%APPDATA%\Ledge\settings.json`; run setup again from the notification-area
icon (**Change what Ledge shows…**).

Open, Home shows what's playing (previous, play/pause, next), your next meeting, the battery and Keep
awake. The tabs your personas switch on sit beside it:

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

Alerts slide out of the closed island when you plug in, when the battery drops to 20% and 10%, when a
timer ends, two minutes before a meeting, when an app turns on the microphone or camera, and when Claude
Code or Codex finishes or needs you.

**Coding agent alerts** are connected from the notification-area icon (**Coding agent alerts**). Ledge
adds two hooks to `~/.claude/settings.json` and a `notify` line to `~/.codex/config.toml`, each running
`Ledge.exe --agent …`; both files are backed up first (`.ledge-backup`), an existing Codex notify program
keeps running after Ledge's, and disconnecting removes only what Ledge added. If you move `Ledge.exe`,
the hooks follow it the next time it starts.

## Build it yourself

Needs Windows 10 (2004) or later and the [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0).

```powershell
dotnet run --project windows/Ledge
dotnet test windows/Ledge.Tests
```

Every push that touches `windows/` is built on GitHub Actions for x64 and Arm64; the builds are
attached to the run as artifacts. A copy run straight from a build never updates itself.

## Releasing

Push a tag named `windows-v` and the version, for example `windows-v0.1.0`. The
[Windows release workflow](../.github/workflows/windows-release.yml) runs the tests, builds the installer
with [Velopack](https://velopack.io) and publishes a GitHub release with it. Windows releases are never
marked latest, so the Mac download links and the Homebrew tap keep pointing at the Mac release. The
website finds the newest `windows-v` release on its own and offers it to visitors on Windows.
