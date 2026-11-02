# Ledge for Windows

Early work on a Windows version of Ledge. Windows laptops have no notch, so the island floats as a pill
at the top centre of the screen. Rest the pointer on it, push the pointer against the top edge above it,
or tap it to open it. Ledge's icon in the notification area has the menu: a test alert, start at sign-in,
and Quit.

Open, it has three tabs:

- **Home**: what's playing in any app that reports to Windows' media controls, with previous, play/pause
  and next; the battery; and Keep awake, which stops the screen turning off.
- **Timer**: 5, 15 or 25 minutes, with pause, +1 min and cancel. It counts down in the closed island too.
- **Ports**: dev servers listening on localhost, with Open in browser and Stop (click twice).

Closed, the island shows a running timer or what's playing, and alerts slide out of it when you plug in,
when the battery drops to 20% and 10%, and when a timer ends.

Needs Windows 10 (2004) or later and the [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0).

```powershell
dotnet run --project windows/Ledge
dotnet test windows/Ledge.Tests
```

Every push that touches `windows/` is built on GitHub Actions for x64 and Arm64; the builds are
attached to the run as artifacts.
