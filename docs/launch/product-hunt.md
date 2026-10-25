# Product Hunt

Launch on a Tuesday, Wednesday or Thursday. The day starts at 12:01 a.m. Pacific, so schedule the post
for then and be around for the first few hours to answer comments.

Before launch day: a download link that works, the trial, and the license purchase (the page and
posts say "7 days free, then $19.99 once", and none of that is built yet).

## Name

Kestrel

## Tagline (60 characters max)

> The MacBook notch, turned into the tools you use all day

Alternatives:
- Your MacBook notch, arranged around what you do
- Music, agents, files and shortcuts, right under the notch

## Description (260 characters max)

> Hover the notch and Kestrel opens: what's playing, your week, your files, Claude and Codex usage.
> While it's closed, small alerts slide out beside it. Tell it what you do (developer, designer,
> student…) and it sets itself up around that. $19.99 once.

## Topics

Mac, Productivity, Developer Tools, Design Tools

## Gallery (1270×760)

1. The demo video (see `demo-video.md`), poster from shot 2.
2. `hero-open.png` on the dusk background: "Hover the notch. Everything's there."
3. `setup-personas.png`: "Tell it what you do."
4. `home-developer.png` and `home-designer.png` side by side: "Same app, set up for different people."
5. Banners: agent, meeting, mic, volume: "Quiet, until something needs you."
6. `tab-stats.png`: "Claude and Codex limits, CPU, memory, network."
7. `tab-ports.png`: "Every localhost server, one click to open or stop."

Lay each still on the dusk panel the site uses (`.screen-slice`), so the black island doesn't vanish
into a dark gallery.

## First comment, from the maker

> Hi Product Hunt 👋
>
> The notch on my MacBook was the one part of the screen doing nothing, so I built Kestrel to put it
> to work.
>
> Hover it and it opens into a small island: what's playing (with synced lyrics), your week, a file
> shelf, clipboard history, notes, timers. When it's closed it stays out of the way, and short alerts
> slide out beside it instead: volume, AirPods battery, a meeting about to start, a muted mic.
>
> The part I care most about: the first time it opens, you pick what you do. Developers get Claude and
> Codex usage, alerts when an agent is waiting on them, and their localhost ports. Designers get a
> color picker and an image-friendly shelf. Students get a focus timer and notes. You can pick more
> than one, and change any of it later.
>
> A few things I held to:
> - Everything stays on your Mac. The only network calls are lyrics lookups and your Claude usage.
> - One price, $19.99, no subscription. Try it free for 7 days.
> - Native Swift, no Electron.
>
> I'd love to hear what you'd want in the notch that isn't there yet.

## Replies to have ready

- **"How is this different from NotchNook / Boring Notch / Alcove?"** Those are great at media and
  files. Kestrel sets itself up around what you do, and it goes further for developers: Claude and
  Codex limits, agent alerts, ports.
- **"Does it work on Macs without a notch?"** Yes, it sits at the top of the screen as a pill.
- **"Why does it need Accessibility?"** For window snapping and to show volume and brightness in the
  notch. Everything else works without it. Details: the privacy page.
- **"Is the Claude usage official?"** It reads the usage Claude Code already shows, using the login
  Claude Code saved. Anthropic hasn't published this as a public API, so it could change.
