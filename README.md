# Ledge

Ledge turns the MacBook notch into a small, quiet island of everyday tools. Hover the notch and it
opens: what's playing, your week, quick actions, and a single status row for everything else. Brief
alerts (volume, battery, a meeting starting, an AI agent waiting on you) slide out beside the notch
while it's closed. On Macs without a notch it sits at the top of the screen as a pill.

On first launch you tell Ledge what you do, and it arranges itself around that.

## What you do decides what you get

Pick one or more in setup (or later in Settings). Each persona ranks the tools; Ledge switches on
what fits, puts your most-used tabs nearest the notch, and chooses what Home and the closed notch show.

| Persona | Leads with |
| --- | --- |
| Developer | Claude and Codex usage, agent alerts, localhost ports, clipboard, notes |
| Designer | Color picker, file shelf, image clipboard, screenshots |
| Creator | Now playing, timers, mic and camera indicator, audio output |
| Student | Focus timer, notes, calendar |
| Professional | Meetings and meeting countdowns, mic mute, world clock, notes |
| Essentials | Music, shelf, clipboard, calendar |

Mixed personas take each tool at its best rank; the first one picked breaks ties and decides Home.
Every tool can still be switched on or off in Settings.

## Tools

**In the island:** Home · Now playing with synced lyrics · File shelf · Color picker · Clipboard
history · Timer and focus sessions · Notes · System stats (CPU, memory, network, battery, Claude and
Codex limits) · Localhost ports · Calendar week on Home

**Everywhere:** Volume and brightness in the notch · Battery and AirPods alerts · Meeting countdown ·
Agent alerts for Claude Code and Codex · Mic mute · Mic and camera in use · Window snapping · Keep
awake · Screenshots · Audio output switching · World clock · Menu bar icon settings

| Shortcut | Does |
| --- | --- |
| ⌃⌥ ← → ↑ ↓ | Snap the front window to a half of the screen |
| ⌃⌥ ↩ | Fill the screen with the front window |
| ⌃⌥ S | Screenshot an area (saved, copied, and put on the shelf) |
| ⌃⌥ P | Pick a color anywhere on screen |
| ⌃⌥ M | Mute or unmute the microphone |

## Privacy

Everything stays on the Mac. Clipboard history is kept in memory only, and items password managers
mark as secret are skipped. Notes are a file in `~/Library/Application Support/Ledge`. Calendar
events are read through macOS's own calendar access and never leave the Mac.

Two things go over the network: synced lyrics are looked up on [LRCLIB](https://lrclib.net) by song
title and artist, and the Claude usage meter asks Anthropic's API using the login Claude Code already
saved in your Keychain (read only; Ledge never refreshes or changes it).

Agent alerts, when you connect them in Settings, add a small command to `~/.claude/settings.json`
and `~/.codex/config.toml`. Ledge asks first, saves a backup of each file next to it, and keeps an
existing Codex `notify` command working by running it afterwards. Disconnect removes it again.

## Building

Requires macOS 14 or later, Apple Silicon, Xcode (Swift 6) and CMake.

```bash
./build.sh && open build/Ledge.app
```

`build.sh` fetches and builds [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter),
builds the app, and assembles `build/Ledge.app`. Tests: `swift test`.

Builds are signed ad hoc, for the Mac they're built on. macOS treats each build as a new app, so after
rebuilding, remove and re-add Ledge under System Settings › Privacy & Security › Accessibility.

To review the design without clicking through it, `open build/Ledge.app --args --snapshot <folder>`
renders every persona, tab, setup step and closed-notch banner to PNGs and quits. It previews layouts
without changing your settings.

## Layout

```
Sources/Ledge/
  LedgeApp.swift       app entry, menu bar item, Settings window
  NotchPanel.swift       the island window, hover, banners, tool wiring
  NotchView.swift        island shell: closed states, tab pills, open layout
  Design.swift           colours, type scale, motion, notch shape, icons, buttons
  Persona.swift          personas and how they merge into a layout
  Preferences.swift      tools, switches, Settings
  Onboarding.swift       setup inside the island
  MediaTab.swift, NowPlaying.swift, Lyrics.swift, Usage.swift
  Tools/                 one file per tool
Icons/                   Solar icons (SVG) and the Claude and Codex marks
Tests/LedgeTests/
```

## Credits

- Icons: [Solar](https://www.figma.com/community/file/1166831539721848736) by 480 Design, CC BY 4.0,
  via [Iconify](https://iconify.design). Credited in Settings as the license requires.
- Now playing: [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den
  Berg, BSD 3-Clause; its license ships inside the app.
- Synced lyrics: [LRCLIB](https://lrclib.net).
- The Claude and Codex marks belong to Anthropic and OpenAI and identify whose usage is shown.

## Trial and license

Ledge is free for 7 days, then needs a [Lemon Squeezy](https://www.lemonsqueezy.com) license key
(two Macs per key). Once the trial ends the island shows how to buy and every tool stops; Settings ›
License takes the key. The trial start and key live in the login keychain. `License.swift` holds the
store and product IDs and the checkout link; the site's Buy button uses the same link.

`./build.sh dmg` also packs `site/Ledge.dmg`, which the site's Download buttons link to.

## Before selling

- In Lemon Squeezy, create the $19.99 product with license keys on and an activation limit of 2,
  then put its store ID, product ID and checkout link in `License.swift` and the checkout link in
  `site/index.html`. Until then any Lemon Squeezy key is accepted.
- Sign with a Developer ID and notarize; add Sparkle for updates.
- Lyrics come from a crowd-sourced service without a lyrics license.
- The Claude usage endpoint is undocumented; check Anthropic's terms for this use of Claude Code's login.
- Now playing and brightness use private macOS APIs that can change in updates.
- Confirm the Ledge name with a trademark search.
