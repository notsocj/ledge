# Demo video

One video, about 40 seconds, used three ways: the landing page hero, the first Product Hunt gallery
slot, and the r/macapps post. No voice-over; it has to make sense muted.

Snapshot mode (`--snapshot`) gives you the stills (they're already in `site/assets`). Motion has to be
recorded from the real app.

## Set up the Mac

- A dark, plain wallpaper. The page uses dusk blue (`#10203a`), so a solid colour near that keeps
  video and stills matching.
- Hide desktop icons: `defaults write com.apple.finder CreateDesktop false && killall Finder`
  (set it back to `true` afterwards).
- Turn on Do Not Disturb, and quit anything that shows its own notifications.
- Leave only a few menu bar icons.
- Set the pointer to a normal size. Hover is the whole interaction, so the pointer has to be easy to follow.
- Music: play a track you have the rights to, or a royalty-free one, with your own artwork. Real
  album art and lyrics can't go in a public video. The demo song from the snapshots ("Afterglow" by
  "Northbound") only exists in snapshot mode.
- Use a fresh setup so the persona step can be recorded: quit Ledge, run
  `defaults delete com.ledge.Ledge onboarded`, and open it again.

## Record

⇧⌘5, then Record Selected Portion. Drag the frame over the top third of the screen, centred on the
notch, at a 16:9 shape. Turn on "Show Mouse Clicks" in Options. Record each shot separately and cut
them together; it's easier to retake one shot than the whole thing.

## Shots

| # | Length | What happens on screen | Shows |
| --- | --- | --- | --- |
| 1 | 3s | Closed notch, music playing. Artwork on the left, bars on the right. | It lives in the notch |
| 2 | 5s | Pointer moves up, island opens on Home: song, week, status row. | Hover to open |
| 3 | 6s | Setup: pick Developer, then Designer. The tab row changes under it. | Built around what you do |
| 4 | 5s | Click through Music (lyrics scrolling), Stats, Ports. | What's inside |
| 5 | 4s | Pointer leaves, island closes. Press the volume key, a slim level slides out. | Quiet until needed |
| 6 | 5s | In a terminal, Claude Code finishes. "Needs you" banner appears beside the notch. | Agent alerts |
| 7 | 4s | ⌃⌥ ← snaps a window to the left half, ⌃⌥ P picks a colour. | Everywhere else |
| 8 | 4s | Drag a file onto the notch; it lands on the shelf. | Shelf |
| 9 | 3s | End card: icon, "Ledge", "The notch, put to work." | |

For shot 6 without waiting on a real agent, run the alert directly:
`open -g "ledge://agent/claude/waiting?project=ledge"` ("done" instead of "waiting" shows the
finished banner).

## Edit and export

- Cut on motion: each new shot starts as the island starts to move.
- No music bed is needed. If you add one, keep it quiet and licensed.
- Export three files:
  - `demo.mp4`, H.264, 1920×1080, for Product Hunt and Reddit.
  - `demo-hero.mp4` and `demo-hero.webm`, under 4 MB, muted, for the landing page.
  - A 1270×760 PNG poster from shot 2, for the Product Hunt thumbnail.

## Put it on the page

The hero image already sits in `.screen` in `site/index.html`. When the clip is ready, swap the two
hero images for:

```html
<video class="hero-video" autoplay muted loop playsinline poster="assets/hero-open.png">
  <source src="assets/demo-hero.webm" type="video/webm">
  <source src="assets/demo-hero.mp4" type="video/mp4">
</video>
```

Keep the current hover island as the fallback for `prefers-reduced-motion`, where the video
shouldn't autoplay.
