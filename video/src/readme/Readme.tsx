import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {C, FONT, Island, IslandSize, Pinned, clamp, ease, islandSpring, mix, settle} from '../lib';

// Pictures for the README. The island images are 2x renders from `--snapshot`, shown at their own size.

type Shot = {src: string; w: number; h: number};
const shot = (src: string, w: number, h: number): Shot => ({src: `img/${src}.png`, w, h});
const CLOSED = shot('hero-closed', 546, 64);
const MEETING = shot('banner-meeting', 866, 64);
const HOME = shot('hero-open', 1118, 358);

/** The island's outline for a shot: shallow shoulders when it's notch-high, the open island's when it's tall. */
const sizeOf = (s: Shot): IslandSize => (s.h <= 64 ? {width: s.w, height: s.h, t: 12, b: 24} : {width: s.w, height: s.h, t: 28, b: 64});

/** A slice of the top of a Mac screen: the menu bar, and the notch in the middle of it. */
const Screen: React.FC<{width: number; height: number; children: React.ReactNode; still?: boolean; words?: number}> = ({width, height, children, still, words = still ? 0 : 1}) => (
  <div
    style={{
      position: 'relative',
      width,
      height,
      background: `linear-gradient(${C.night}, ${C.dusk})`,
      borderRadius: still ? 28 : 0,
      outline: still ? '2px solid rgba(255,255,255,0.08)' : undefined,
      overflow: 'hidden',
    }}
  >
    <div
      style={{
        position: 'absolute',
        inset: '0 0 auto 0',
        height: 64,
        background: 'rgba(255,255,255,0.06)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '0 30px',
        fontFamily: FONT,
        fontSize: 26,
        fontWeight: 500,
        color: 'rgba(255,248,239,0.55)',
      }}
    >
      <span style={{wordSpacing: 22, opacity: words}}>
        <b style={{color: 'rgba(255,248,239,0.8)'}}>Finder</b> File Edit View
      </span>
      <span style={{opacity: words}}>Tue 28 Oct 9:41</span>
    </div>
    {children}
  </div>
);

// The loop: closed, a meeting alert, back, then open and through four tabs, and closed again.
const LOOP: {at: number; shot: Shot}[] = [
  {at: 0, shot: CLOSED},
  {at: 30, shot: MEETING},
  {at: 85, shot: CLOSED},
  {at: 110, shot: HOME},
  {at: 160, shot: shot('tab-music', 1118, 362)},
  {at: 198, shot: shot('tab-stats', 1118, 304)},
  {at: 236, shot: shot('tab-ports', 1118, 346)},
  {at: 274, shot: shot('tab-colors', 1118, 286)},
  {at: 318, shot: CLOSED},
];
export const LOOP_FRAMES = 350;

export const ReadmeLoop: React.FC = () => {
  const f = useCurrentFrame();
  const {fps, width, height} = useVideoConfig();
  const i = LOOP.reduce((found, k, n) => (f >= k.at ? n : found), 0);
  const prev = LOOP[Math.max(0, i - 1)];
  const cur = LOOP[i];
  // Opening gets the island's spring, everything else settles without overshoot.
  const opening = cur.shot.h > 64 && prev.shot.h <= 64;
  const p = i === 0 ? 1 : opening ? islandSpring(f, fps, cur.at) : settle(f, fps, cur.at, 220);
  const size = mix(sizeOf(prev.shot), sizeOf(cur.shot), p);
  return (
    <AbsoluteFill>
      {/* The menu bar's words step aside as the island grows over them, instead of being cut mid-word. */}
      <Screen width={width} height={height} words={interpolate(size.width, [560, 820], [1, 0], clamp)}>
        <Island size={size} centerX={width / 2}>
          {LOOP.map((k, n) => {
            const end = LOOP[n + 1]?.at ?? LOOP_FRAMES;
            const enter = n === 0 ? 1 : interpolate(f, [k.at + 4, k.at + 14], [0, 1], {...clamp, easing: ease.out});
            const exit = interpolate(f, [end, end + 6], [0, 1], clamp);
            const vis = enter * (1 - exit);
            if (vis <= 0) return null;
            return (
              <Pinned key={n} width={k.shot.w} height={k.shot.h} style={{opacity: vis, filter: `blur(${(1 - enter) * 8}px)`}}>
                <Img src={staticFile(k.shot.src)} style={{width: k.shot.w, height: k.shot.h}} />
              </Pinned>
            );
          })}
        </Island>
      </Screen>
    </AbsoluteFill>
  );
};

/** The island at rest on a screen slice, for the stills. */
const Still: React.FC<{s: Shot; width: number; height: number}> = ({s, width, height}) => (
  <Screen width={width} height={height} still>
    <Island size={sizeOf(s)} centerX={width / 2}>
      <Img src={staticFile(s.src)} style={{width: s.w, height: s.h}} />
    </Island>
  </Screen>
);

const caption: React.CSSProperties = {fontFamily: FONT, fontSize: 34, lineHeight: 1.35, color: C.cream, marginTop: 20, marginBottom: 44};
const label: React.CSSProperties = {fontWeight: 700};
const PAD = 56;
const card: React.CSSProperties = {background: C.night, borderRadius: 44, padding: PAD};

/** Closed, alerting, open: the three ways the island shows up. */
export const ReadmeMoments: React.FC = () => (
  <AbsoluteFill style={card}>
    {[
      {s: CLOSED, h: 140, title: 'Closed.', text: 'It looks like the notch. The wings show what’s playing, or a timer.'},
      {s: MEETING, h: 140, title: 'Something happens.', text: 'An alert slides out: a meeting, a low battery, an agent waiting.'},
      {s: HOME, h: 440, title: 'Hover.', text: 'It opens. Your tools, and what you were doing, in one place.'},
    ].map(({s, h, title, text}) => (
      <div key={title}>
        <Still s={s} width={1280} height={h} />
        <div style={caption}>
          <span style={label}>{title}</span> <span style={{color: C.mist}}>{text}</span>
        </div>
      </div>
    ))}
  </AbsoluteFill>
);
export const MOMENTS_WIDTH = 1280 + 2 * PAD;
export const MOMENTS_HEIGHT = 140 + 140 + 440 + 3 * 110 - 44 + 2 * PAD;

const PERSONAS = [
  {name: 'Developer', src: 'home-developer', h: 358, leads: 'Claude and Codex usage, agent alerts, ports'},
  {name: 'Designer', src: 'home-designer', h: 358, leads: 'Color picker, file shelf, screenshots'},
  {name: 'Creator', src: 'home-creator', h: 328, leads: 'Now playing, timers, mic and camera'},
  {name: 'Student', src: 'home-student', h: 358, leads: 'Focus timer, notes, calendar'},
  {name: 'Professional', src: 'home-professional', h: 358, leads: 'Meetings, mic mute, world clock'},
  {name: 'Essentials', src: 'home-essentials', h: 358, leads: 'Music, shelf, clipboard, calendar'},
];

/** Six people, six Homes: what you pick in setup decides what the island leads with. */
export const ReadmePersonas: React.FC = () => (
  <AbsoluteFill style={{...card, display: 'grid', gridTemplateColumns: '1240px 1240px', columnGap: 40, alignContent: 'start'}}>
    {PERSONAS.map((p) => (
      <div key={p.name}>
        <Still s={shot(p.src, 1118, p.h)} width={1240} height={410} />
        <div style={{...caption, fontSize: 50, marginBottom: 50}}>
          <span style={label}>{p.name}</span> <span style={{color: C.mist}}>{p.leads}</span>
        </div>
      </div>
    ))}
  </AbsoluteFill>
);
export const PERSONAS_WIDTH = 2 * 1240 + 40 + 2 * PAD;
export const PERSONAS_HEIGHT = 3 * (410 + 138) - 50 + 2 * PAD; // caption: 50px type at 1.35, 20 above, 50 below
