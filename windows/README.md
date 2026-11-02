# Ledge for Windows

Early work on a Windows version of Ledge. Windows laptops have no notch, so the island floats as a pill
at the top centre of the screen. Right-click it to quit.

Needs Windows 10 (2004) or later and the [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0).

```powershell
dotnet run --project windows/Ledge
```

Every push that touches `windows/` is built on GitHub Actions for x64 and Arm64; the builds are
attached to the run as artifacts.
