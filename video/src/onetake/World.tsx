import React from 'react';
import {Img, interpolate, random, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {BANNER, C, FONT, Island, IslandSize, NOTCH, OPEN, Pinned, clamp, ease, islandSpring, mix, settle} from '../lib';
import {T, cursorAt, keys} from './rig';

export const SCREEN = {w: 1920, h: 1200};

/** Dusk wallpaper: the sky the site and icon come from, with soft hills and a few stars. */
const Wallpaper: React.FC = () => (
  <div style={{position: 'absolute', inset: 0, background: `linear-gradient(180deg, ${C.night} 0%, ${C.dusk} 45%, #2b4f82 78%, #5a83b6 100%)`}}>
    {Array.from({length: 60}, (_, i) => (
      <div
        key={i}
        style={{
          position: 'absolute',
          left: random(`wx${i}`) * 1920,
          top: 60 + random(`wy${i}`) * 520,
          width: 2 + random(`wr${i}`) * 2,
          height: 2 + random(`wr${i}`) * 2,
          borderRadius: '50%',
          background: '#fff',
          opacity: 0.2 + random(`wa${i}`) * 0.5,
        }}
      />
    ))}
    <svg width={1920} height={1200} style={{position: 'absolute', inset: 0}}>
      <path d="M0 980 C 300 860 520 900 760 940 C 1010 980 1180 860 1420 880 C 1640 900 1800 960 1920 930 L1920 1200 L0 1200 Z" fill="#16294a" />
      <path d="M0 1060 C 260 1010 560 1030 840 1070 C 1100 1105 1380 1010 1920 1050 L1920 1200 L0 1200 Z" fill="#0d1a31" />
    </svg>
  </div>
);

const MenuBar: React.FC = () => {
  const item: React.CSSProperties = {fontFamily: FONT, fontSize: 24, fontWeight: 600, color: 'rgba(255,255,255,0.92)'};
  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        top: 0,
        height: 52,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '0 30px',
        background: 'rgba(10,18,32,0.45)',
      }}
    >
      <div style={{display: 'flex', gap: 36, ...item}}>
        <span style={{fontWeight: 700}}>Code</span>
        <span>File</span>
        <span>Edit</span>
        <span>Selection</span>
        <span>View</span>
      </div>
      <div style={{display: 'flex', gap: 30, ...item}}>
        <span>100%</span>
        <span>Mon 9:41 AM</span>
      </div>
    </div>
  );
};

const Window: React.FC<{x: number; y: number; w: number; h: number; title: string; children: React.ReactNode}> = ({x, y, w, h, title, children}) => (
  <div
    style={{
      position: 'absolute',
      left: x,
      top: y,
      width: w,
      height: h,
      borderRadius: 22,
      background: 'rgba(16,20,28,0.92)',
      boxShadow: '0 40px 90px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.08)',
      overflow: 'hidden',
    }}
  >
    <div style={{height: 52, display: 'flex', alignItems: 'center', gap: 12, padding: '0 20px', background: 'rgba(255,255,255,0.04)'}}>
      {['#ff5f57', '#febc2e', '#28c840'].map((c) => (
        <div key={c} style={{width: 16, height: 16, borderRadius: 8, background: c}} />
      ))}
      <span style={{fontFamily: FONT, fontSize: 20, fontWeight: 600, color: 'rgba(255,255,255,0.5)', marginLeft: 14}}>{title}</span>
    </div>
    <div style={{padding: '22px 28px', fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace', fontSize: 22, lineHeight: '36px'}}>{children}</div>
  </div>
);

const CODE: [string, string][][] = [
  [['#c678dd', 'struct '], ['#e5c07b', 'NotchView'], ['#abb2bf', ': View {']],
  [['#abb2bf', '    '], ['#c678dd', 'let '], ['#e06c75', 'app'], ['#abb2bf', ': NotchController']],
  [['#abb2bf', '    '], ['#c678dd', 'var '], ['#e06c75', 'body'], ['#abb2bf', ': '], ['#c678dd', 'some '], ['#e5c07b', 'View'], ['#abb2bf', ' {']],
  [['#abb2bf', '        '], ['#61afef', 'Island'], ['#abb2bf', '(open: hovering)']],
  [['#abb2bf', '            .'], ['#61afef', 'animation'], ['#abb2bf', '(.'], ['#98c379', 'spring'], ['#abb2bf', ')']],
  [['#abb2bf', '    }']],
  [['#abb2bf', '}']],
  [['#5c6370', '// the notch, put to work']],
];

const Editor: React.FC = () => (
  <Window x={110} y={240} w={880} h={560} title="NotchView.swift">
    {CODE.map((line, i) => (
      <div key={i} style={{whiteSpace: 'pre'}}>
        {line.map(([color, text], j) => (
          <span key={j} style={{color}}>
            {text}
          </span>
        ))}
      </div>
    ))}
  </Window>
);

/** A Claude Code session that finishes and asks for you: the moment the notch taps your shoulder. */
const Terminal: React.FC = () => {
  const f = useCurrentFrame();
  const waiting = f >= T.alerts[0] - 4;
  const spinner = ['✻', '✳', '✢', '·'][Math.floor(f / 4) % 4];
  return (
    <Window x={1040} y={460} w={790} h={440} title="claude — ~/ledge">
      <div style={{color: '#abb2bf'}}>
        <span style={{color: '#d97757'}}>›</span> polish the island motion
      </div>
      <div style={{color: '#5c6370'}}>  Read 12 files, edited NotchView.swift</div>
      <div style={{color: '#5c6370'}}>  Ran swift test: 31 passed</div>
      <div style={{color: waiting ? '#e5c07b' : '#d97757'}}>
        {waiting ? '● Waiting for your answer' : `${spinner} Working…`}
      </div>
    </Window>
  );
};

const TABS = [
  {src: 'img/all-home.png', h: 179},
  {src: 'img/all-media.png', h: 181},
  {src: 'img/all-home.png', h: 179},
  {src: 'img/all-stats.png', h: 152},
  {src: 'img/all-ports.png', h: 173},
];
const TAB_STARTS = [T.open, ...T.clicks.map((c) => c + 1)];
const BANNERS = [
  {src: 'img/banner-agent.png', w: 433},
  {src: 'img/banner-meeting.png', w: 433},
  {src: 'img/banner-mic.png', w: 377},
];
const BANNER_ENDS = [T.alerts[1] - 2, T.alerts[2] - 2, T.carousel - 10];

/** The island over the whole take: opens on hover, changes tab on each click, closes, then fires alerts. */
const LiveIsland: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  let size: IslandSize = NOTCH;
  let layers: React.ReactNode = null;
  if (f >= T.open && f < T.close + 30) {
    const open = islandSpring(f, fps, T.open);
    const close = settle(f, fps, T.close, 200);
    const tab = TAB_STARTS.reduce((found, s, i) => (f >= s ? i : found), 0);
    const grow = settle(f, fps, TAB_STARTS[tab], 220);
    const prevH = TABS[Math.max(0, tab - 1)].h * 2.2;
    const height = prevH + (TABS[tab].h * 2.2 - prevH) * grow;
    size = mix(mix(NOTCH, {...OPEN, height}, open), NOTCH, close);
    layers = TABS.map((t, i) => {
      const start = TAB_STARTS[i], end = TAB_STARTS[i + 1] ?? 10_000;
      const enter = i === 0 ? interpolate(f, [start + 4, start + 16], [0, 1], clamp) : interpolate(f, [start, start + 7], [0, 1], {...clamp, easing: ease.out});
      const exit = interpolate(f, [end, end + 5], [0, 1], clamp);
      const vis = enter * (1 - exit) * (1 - close);
      if (vis <= 0) return null;
      return (
        <Pinned key={i} width={OPEN.width} height={t.h * 2.2} style={{opacity: vis, filter: `blur(${(1 - enter) * 8}px)`}}>
          <Img src={staticFile(t.src)} style={{width: OPEN.width, height: t.h * 2.2}} />
        </Pinned>
      );
    });
  }
  const alert = T.alerts.reduce((found, s, i) => (f >= s ? i : found), -1);
  if (alert >= 0 && f < BANNER_ENDS[alert] + 8) {
    const b = BANNERS[alert];
    const open = islandSpring(f, fps, T.alerts[alert]);
    const back = interpolate(f, [BANNER_ENDS[alert] - 6, BANNER_ENDS[alert]], [0, 1], {...clamp, easing: ease.inOut});
    size = mix(NOTCH, {...NOTCH, width: b.w * BANNER}, open * (1 - back));
    const shown = interpolate(open, [0.35, 0.9], [0, 1], clamp) * (1 - back);
    layers = (
      <Pinned width={b.w * BANNER} height={52} style={{opacity: shown}}>
        <Img src={staticFile(b.src)} style={{width: b.w * BANNER, height: 52}} />
      </Pinned>
    );
  }
  // The tap on the shoulder: the alert bounces.
  const tap = 1 + 0.22 * Math.exp(-(((f - T.tap) / 4) ** 2));
  // Bored at the idle notch: it sighs a little.
  const sigh = f > T.idle && f < T.pullBack ? 1 + 0.03 * Math.sin((f - T.idle) / 7) : 1;
  return (
    <div style={{position: 'absolute', inset: 0, transformOrigin: '960px 0px', scale: `${tap * sigh} ${tap}`}}>
      <Island size={size}>{layers}</Island>
    </div>
  );
};

/** The macOS pointer, with a ring on every click. */
const Cursor: React.FC = () => {
  const f = useCurrentFrame();
  const {x, y} = cursorAt(f);
  const visible = interpolate(f, [T.leave + 6, T.leave + 20], [1, 0], clamp);
  if (visible <= 0) return null;
  const press = T.clicks.reduce((s, at) => s + Math.exp(-(((f - at) / 2.5) ** 2)), 0);
  return (
    <>
      {T.clicks.map((at) => {
        const p = interpolate(f, [at, at + 16], [0, 1], {...clamp, easing: ease.out});
        if (f < at || p >= 1) return null;
        return (
          <div
            key={at}
            style={{
              position: 'absolute',
              left: x - 40,
              top: y - 40,
              width: 80,
              height: 80,
              borderRadius: 40,
              border: `4px solid ${C.cream}`,
              scale: `${0.3 + p * 1.2}`,
              opacity: (1 - p) * 0.9,
            }}
          />
        );
      })}
      <svg
        width={44}
        height={60}
        viewBox="0 0 22 30"
        style={{
          position: 'absolute',
          left: x - 3,
          top: y - 2,
          opacity: visible,
          scale: `${1 - press * 0.18}`,
          transformOrigin: '3px 2px',
          filter: 'drop-shadow(0 4px 6px rgba(0,0,0,0.45))',
        }}
      >
        <path d="M2 1 L2 23 L7.5 17.8 L11.2 26.5 L14.6 25 L11 16.6 L18.6 16.6 Z" fill="#000" stroke="#fff" strokeWidth={1.6} strokeLinejoin="round" />
      </svg>
    </>
  );
};

/** Little z's drifting off the bored notch. */
const Snooze: React.FC = () => {
  const f = useCurrentFrame();
  if (f < T.idle || f > T.pullBack + 10) return null;
  return (
    <>
      {[0, 1, 2].map((i) => {
        const start = T.idle + 10 + i * 26;
        const p = interpolate(f, [start, start + 50], [0, 1], clamp);
        if (p <= 0 || p >= 1) return null;
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: 1110 + p * 70 + i * 10,
              top: 60 - p * 30 + i * 6,
              fontFamily: FONT,
              fontWeight: 800,
              fontSize: 26 + i * 8,
              color: C.mist,
              opacity: Math.sin(Math.PI * p),
              rotate: `${-10 + p * 20}deg`,
            }}
          >
            z
          </div>
        );
      })}
    </>
  );
};

/** The MacBook: its screen (everything above), a bezel, and a keyboard deck that shows when the camera orbits. */
export const MacBook: React.FC = () => {
  const f = useCurrentFrame();
  const ry = keys(f, [
    [T.orbit, 0],
    [T.orbit + 40, -16],
    [T.alerts[2] + 10, 10],
    [T.carousel, 6],
    [T.dive - 10, 0],
  ]);
  const rx = keys(f, [
    [T.orbit, 0],
    [T.orbit + 30, 10],
    [T.alerts[2] + 10, 6],
    [T.dive - 10, 0],
  ]);
  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        top: 0,
        width: SCREEN.w,
        height: SCREEN.h,
        transformStyle: 'preserve-3d',
        transform: `rotateX(${rx}deg) rotateY(${ry}deg)`,
        transformOrigin: '960px 700px',
      }}
    >
      <div
        style={{
          position: 'absolute',
          left: -220,
          top: SCREEN.h + 34,
          width: SCREEN.w + 440,
          height: 1250,
          borderRadius: '24px 24px 60px 60px',
          background: 'linear-gradient(180deg, #4b5159 0%, #2f343b 60%, #24282e 100%)',
          transformOrigin: '50% 0%',
          transform: 'rotateX(82deg)',
          boxShadow: 'inset 0 4px 0 rgba(255,255,255,0.12)',
        }}
      />
      <div
        style={{
          position: 'absolute',
          inset: -34,
          borderRadius: 60,
          background: '#0a0b0e',
          boxShadow: '0 0 0 5px #3d424a, 0 60px 160px rgba(0,0,0,0.6)',
        }}
      />
      <div style={{position: 'absolute', inset: 0, borderRadius: 26, overflow: 'hidden'}}>
        <Wallpaper />
        <Editor />
        <Terminal />
        <MenuBar />
        <Snooze />
        <LiveIsland />
        <Cursor />
      </div>
    </div>
  );
};
