import React from 'react';
import {Audio} from '@remotion/media';
import {AbsoluteFill, Img, interpolate, Sequence, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {C, FONT, Island, IslandSize, Letters, Words, clamp, ease, slot} from '../lib';
import {T, camAt, keys, toScreen} from './rig';
import {MacBook} from './World';

/** The camera: the MacBook seen through a moving, zooming, banking lens, with blur from its own speed. */
const Camera: React.FC = () => {
  const f = useCurrentFrame();
  const c = camAt(f);
  const dim = keys(f, [
    [T.carousel - 4, 0],
    [T.carousel + 12, 1],
    [T.collapse, 1],
    [T.dive - 2, 0],
  ]);
  return (
    <AbsoluteFill style={{filter: `url(#speed) blur(${dim * 10}px) brightness(${1 - dim * 0.6})`}}>
      <AbsoluteFill style={{background: 'radial-gradient(80% 90% at 50% 60%, #1b2a44 0%, #0b1220 55%, #04070d 100%)'}} />
      <svg width={0} height={0} style={{position: 'absolute'}}>
        <filter id="speed" x="-10%" y="-10%" width="120%" height="120%">
          <feGaussianBlur stdDeviation={`${c.blurX.toFixed(2)} ${c.blurY.toFixed(2)}`} />
        </filter>
      </svg>
      <div
        style={{
          position: 'absolute',
          left: 0,
          top: 0,
          width: 1920,
          height: 1200,
          transformOrigin: '0 0',
          transform: `translate(960px, 540px) rotate(${c.rot}deg) scale(${c.z}) translate(${-c.x}px, ${-c.y}px)`,
          perspective: 2600,
          perspectiveOrigin: '960px 640px',
        }}
      >
        <MacBook />
      </div>
    </AbsoluteFill>
  );
};

const shadow = '0 10px 40px rgba(0,0,0,0.55), 0 2px 8px rgba(0,0,0,0.4)';

/** Type that lands with weight: pops in a touch big and tilted, settles, and blurs away when done. */
const Pop: React.FC<{
  at: number;
  out: number;
  x?: number;
  y: number;
  size: number;
  color?: string;
  weight?: number;
  tilt?: number;
  children: React.ReactNode;
}> = ({at, out, x = 960, y, size, color = C.cream, weight = 800, tilt = -4, children}) => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  if (f < at - 1 || f > out + 12) return null;
  const s = spring({frame: f - at, fps, config: {damping: 11, stiffness: 180, mass: 0.8}});
  const leave = interpolate(f, [out, out + 10], [0, 1], {...clamp, easing: ease.inOut});
  return (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: y,
        translate: '-50% -50%',
        whiteSpace: 'nowrap',
        fontFamily: FONT,
        fontWeight: weight,
        fontSize: size,
        letterSpacing: '-0.045em',
        lineHeight: 1,
        color,
        textShadow: shadow,
        scale: `${(0.6 + 0.4 * s) * (1 - leave * 0.12)}`,
        rotate: `${(1 - s) * tilt}deg`,
        opacity: Math.min(1, s * 1.6) * (1 - leave),
        filter: `blur(${(1 - Math.min(1, s)) * 10 + leave * 12}px)`,
      }}
    >
      {children}
    </div>
  );
};

/** "absolutely nothing." The last word deflates. */
const Nothing: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const deflate = spring({frame: f - 146, fps, config: {damping: 9, stiffness: 120}});
  return (
    <Pop at={117} out={166} y={930} size={124}>
      absolutely{' '}
      <span style={{display: 'inline-block', transformOrigin: '50% 100%', scale: `${1 + deflate * 0.12} ${1 - deflate * 0.38}`, color: C.mist}}>nothing.</span>
    </Pop>
  );
};

/** "Hover." sticks to the cursor. */
const HoverTag: React.FC = () => {
  const f = useCurrentFrame();
  const p = toScreen(f, {x: 978, y: 30});
  return (
    <Pop at={221} out={246} x={p.x + 200} y={p.y + 230} size={96} tilt={8}>
      Hover.
    </Pop>
  );
};

const TAB_WORDS = ['Your music.', 'Your week.', 'Your Claude limits.', 'Your servers.'];
const TAB_CUES = [291, 323, 353, 391];

/** The four tabs, said as they're clicked: one slot, each line punching the last one up and out. */
const TabWords: React.FC = () => {
  const f = useCurrentFrame();
  if (f < TAB_CUES[0] - 2 || f > T.orbit + 14) return null;
  const leave = interpolate(f, [T.orbit, T.orbit + 12], [0, 1], clamp);
  return (
    <div style={{position: 'absolute', left: 0, right: 0, top: 880, height: 150, overflow: 'hidden', opacity: 1 - leave}}>
      {TAB_WORDS.map((word, i) => {
        const at = slot(f, TAB_CUES[i], TAB_CUES[i + 1], 9);
        if (Math.abs(at) >= 1) return null;
        return (
          <div
            key={word}
            style={{
              position: 'absolute',
              inset: 0,
              textAlign: 'center',
              fontFamily: FONT,
              fontWeight: 800,
              fontSize: 130,
              lineHeight: '150px',
              letterSpacing: '-0.05em',
              color: C.cream,
              textShadow: shadow,
              translate: `0 ${at * 150}px`,
              scale: `${1 - Math.abs(at) * 0.2}`,
            }}
          >
            {word}
          </div>
        );
      })}
    </div>
  );
};

const PERSONAS = [
  {name: 'Developer', src: 'img/home-developer.png', h: 179},
  {name: 'Designer', src: 'img/home-designer.png', h: 179},
  {name: 'Creator', src: 'img/home-creator.png', h: 164},
  {name: 'Student', src: 'img/home-student.png', h: 179},
  {name: 'Professional', src: 'img/home-professional.png', h: 179},
  {name: 'Essentials', src: 'img/home-essentials.png', h: 179},
];
const STEPS = [584, 596, 608, 620]; // each moves the deck one Home along (Developer → Professional)
const CARD_W = 1040; // the panel; the island inside is shown at 1.6x
const ISLAND_W = 559 * 1.6;

/**
 * Every persona's Home in a cover flow. Each Home hangs in the dusk panel the website uses, so the
 * black island reads against the dark; the one in the middle stands forward and carries the name.
 */
const Deck: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  if (f < T.carousel || f > T.dive + 8) return null;
  // One value drives both the cards and the name, so they can never disagree.
  const index = STEPS.reduce((sum, at) => sum + spring({frame: f - at, fps, config: {damping: 200, stiffness: 110}}), 0);
  const appear = spring({frame: f - T.carousel, fps, config: {damping: 200, stiffness: 90}});
  const fold = interpolate(f, [T.collapse, T.dive + 6], [0, 1], {...clamp, easing: ease.inOut});
  const notch = toScreen(f, {x: 960, y: 26});
  const centerY = 440 + (notch.y - 440) * fold;
  const front = Math.round(index);
  return (
    <AbsoluteFill style={{perspective: 2400, perspectiveOrigin: '50% 45%'}}>
      {PERSONAS.map((p, i) => {
        const pos = i - index;
        const away = Math.min(Math.abs(pos), 3);
        const h = p.h * 1.6 + 56;
        const x = pos * 820 * (1 - fold);
        const scale = (1 - away * 0.16) * (0.85 + 0.15 * appear) * (1 - fold * 0.9);
        const opacity = Math.max(0, 1 - away * 0.38) * appear * (1 - fold);
        if (opacity <= 0.01) return null;
        return (
          <div
            key={p.name}
            style={{
              position: 'absolute',
              left: 960 - CARD_W / 2,
              top: centerY - h / 2,
              width: CARD_W,
              height: h,
              borderRadius: 30,
              overflow: 'hidden',
              background: 'radial-gradient(90% 150% at 50% 135%, #4a73a6 0%, #1f3a62 55%, #0f1d33 100%)',
              boxShadow: `0 0 0 1px rgba(255,248,239,${0.1 + 0.1 * (1 - away)}), 0 50px 100px rgba(0,0,0,0.55)`,
              translate: `${x}px 0 ${-away * 180}px`,
              rotate: `0 1 0 ${-Math.max(-1, Math.min(1, pos)) * 24 * (1 - fold)}deg`,
              scale: `${scale}`,
              opacity,
              zIndex: 100 - Math.round(away * 10),
            }}
          >
            <Img src={staticFile(p.src)} style={{position: 'absolute', left: (CARD_W - ISLAND_W) / 2, top: 0, width: ISLAND_W, height: p.h * 1.6}} />
            <div style={{position: 'absolute', inset: 0, background: '#04070d', opacity: away * 0.35}} />
          </div>
        );
      })}
      {/* The name of the Home in the middle, rolling up as the deck moves. */}
      <div style={{position: 'absolute', left: 0, right: 0, top: 700, height: 84, opacity: appear * (1 - Math.min(1, fold * 4))}}>
        {PERSONAS.map((p, i) => {
          const at = Math.max(-1, Math.min(1, i - index));
          if (Math.abs(at) >= 1 && i !== front) return null;
          return (
            <div
              key={p.name}
              style={{
                position: 'absolute',
                inset: 0,
                textAlign: 'center',
                fontFamily: FONT,
                fontWeight: 700,
                fontSize: 60,
                lineHeight: '84px',
                letterSpacing: '-0.025em',
                color: C.cream,
                textShadow: shadow,
                translate: `0 ${at * 24}px`,
                opacity: Math.max(0, 1 - Math.abs(at) * 2.2),
                filter: `blur(${Math.abs(at) * 6}px)`,
              }}
            >
              {p.name}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

/** After the fall into the notch: the icon slams down out of the dark, with light behind it. */
const EndCard: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  if (f < T.black - 2) return null;
  const sky = interpolate(f, [T.slam - 6, T.slam + 30], [0, 1], {...clamp, easing: ease.out});
  const slam = spring({frame: f - T.slam, fps, config: {damping: 11, stiffness: 170, mass: 0.9}});
  const rays = interpolate(f, [T.slam, T.slam + 20], [0, 1], clamp);
  const TILE = 280;
  const notch: IslandSize = {width: (560 / 824) * TILE, height: (168 / 824) * TILE, t: (28 / 824) * TILE, b: (36 / 824) * TILE};
  return (
    <AbsoluteFill style={{background: '#000'}}>
      <AbsoluteFill
        style={{
          opacity: sky,
          background: `radial-gradient(90% 70% at 50% 115%, rgba(67,104,154,0.75), transparent 65%), linear-gradient(180deg, ${C.night}, ${C.dusk})`,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 960 - 700,
          top: 380 - 700,
          width: 1400,
          height: 1400,
          borderRadius: '50%',
          background:
            'repeating-conic-gradient(from 0deg, rgba(255,248,239,0.16) 0deg 6deg, transparent 6deg 22deg)',
          maskImage: 'radial-gradient(closest-side, black 20%, transparent 70%)',
          rotate: `${f * 0.4}deg`,
          opacity: rays * 0.8,
        }}
      />
      {Array.from({length: 18}, (_, i) => {
        const p = interpolate(f, [T.slam, T.slam + 30], [0, 1], {...clamp, easing: ease.out});
        if (f < T.slam || p >= 1) return null;
        const a = (i / 18) * Math.PI * 2;
        const d = 120 + p * (260 + (i % 3) * 70);
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: 960 + Math.cos(a) * d - 5,
              top: 380 + Math.sin(a) * d - 5,
              width: 10,
              height: 10,
              borderRadius: 5,
              background: i % 2 ? C.cream : C.icon,
              opacity: 1 - p,
            }}
          />
        );
      })}
      <div
        style={{
          position: 'absolute',
          left: 960 - TILE / 2,
          top: 380 - TILE / 2,
          width: TILE,
          height: TILE,
          scale: `${2.6 - 1.6 * slam}`,
          rotate: `${(1 - slam) * -12}deg`,
          opacity: interpolate(f, [T.slam - 2, T.slam + 4], [0, 1], clamp),
          filter: `blur(${Math.max(0, 1 - slam) * 16}px) drop-shadow(0 40px 70px rgba(0,0,0,0.55))`,
        }}
      >
        <div style={{position: 'absolute', inset: 0, borderRadius: (186 / 824) * TILE, background: C.icon, overflow: 'hidden'}}>
          <Island size={notch} centerX={TILE / 2} />
        </div>
      </div>
      <AbsoluteFill style={{alignItems: 'center', paddingTop: 590}}>
        <div style={{fontFamily: FONT, fontWeight: 800, fontSize: 170, letterSpacing: '-0.06em', color: C.cream, lineHeight: 1}}>
          <Letters text="Ledge" frame={f} start={690} gap={3} />
        </div>
        <div style={{fontFamily: FONT, fontWeight: 600, fontSize: 66, letterSpacing: '-0.025em', color: C.mist, marginTop: 24}}>
          <Words text="The notch," frame={f} start={720} gap={6} /> <Words text="put to work." frame={f} start={751} gap={5} />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/** Grain, vignette and the fades in and out. */
const Finish: React.FC = () => {
  const f = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const fade = Math.max(interpolate(f, [0, 6], [1, 0], clamp), interpolate(f, [durationInFrames - 24, durationInFrames - 1], [0, 1], clamp));
  const flash = 0.35 * Math.exp(-(((f - T.open) / 3) ** 2)) + 0.25 * Math.exp(-(((f - T.slam) / 3) ** 2));
  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      <svg width={1920} height={1080} style={{position: 'absolute', inset: 0, opacity: 0.08, mixBlendMode: 'overlay'}}>
        <filter id="grain2">
          <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves={2} seed={Math.floor(f / 2) % 50} />
        </filter>
        <rect width="100%" height="100%" filter="url(#grain2)" />
      </svg>
      <AbsoluteFill style={{background: 'radial-gradient(140% 100% at 50% 45%, transparent 55%, rgba(0,0,0,0.6))'}} />
      <AbsoluteFill style={{background: C.cream, opacity: flash, mixBlendMode: 'screen'}} />
      <AbsoluteFill style={{background: '#000', opacity: fade}} />
    </AbsoluteFill>
  );
};

const Line: React.FC<{at: number; from: number; to: number; name: string}> = ({at, from, to, name}) => {
  const {fps} = useVideoConfig();
  return (
    <Sequence name={name} from={at} durationInFrames={Math.round((to - from) * fps) + 2} layout="none">
      <Audio src={staticFile('audio/vo2.mp3')} trimBefore={Math.round(from * fps)} trimAfter={Math.round(to * fps)} />
    </Sequence>
  );
};

const Sfx: React.FC<{at: number; src: string; volume: number; name: string; length?: number}> = ({at, src, volume, name, length = 60}) => (
  <Sequence name={name} from={at} durationInFrames={length} layout="none">
    <Audio src={staticFile(src)} volume={volume} />
  </Sequence>
);

export const OneTake: React.FC = () => {
  const {durationInFrames} = useVideoConfig();
  return (
    <AbsoluteFill style={{background: '#000'}}>
      <Camera />
      <Deck />
      <EndCard />

      <Pop at={20} out={58} y={900} size={120}>See that notch?</Pop>
      <Pop at={76} out={112} y={930} size={84} weight={700} color={C.mist}>It's been doing…</Pop>
      <Nothing />
      <Pop at={181} out={214} y={540} size={170} tilt={6}>Watch this.</Pop>
      <HoverTag />
      <Pop at={250} out={282} y={960} size={124}>It opens.</Pop>
      <TabWords />
      <Pop at={440} out={486} y={930} size={80} weight={700}>And when something needs you…</Pop>
      <Pop at={492} out={556} y={930} size={100} tilt={-6}>it taps you on the shoulder.</Pop>
      <Pop at={575} out={628} y={950} size={100}>Built around what you do.</Pop>

      <Finish />

      {/* Voice, cut from one take at its own pauses. */}
      <Line name="VO notch" at={20} from={0} to={1.0} />
      <Line name="VO nothing" at={75} from={2.0} to={4.95} />
      <Line name="VO watch" at={180} from={5.6} to={6.4} />
      <Line name="VO hover" at={220} from={7.33} to={7.7} />
      <Line name="VO opens" at={250} from={8.48} to={9.2} />
      <Line name="VO tabs" at={290} from={9.82} to={14.1} />
      <Line name="VO shoulder" at={440} from={14.64} to={17.5} />
      <Line name="VO built" at={575} from={18.04} to={19.7} />
      <Line name="VO end" at={690} from={20.43} to={23.3} />

      {/* Music: calm until the island opens, then the beat, then calm again after the drop. */}
      <Sequence name="Calm intro" from={0} durationInFrames={T.open + 6} layout="none">
        <Audio src={staticFile('audio/bed.mp3')} volume={(f) => interpolate(f, [0, 20, T.open - 6, T.open + 6], [0, 0.16, 0.16, 0], clamp)} />
      </Sequence>
      <Sequence name="Beat" from={T.open} durationInFrames={T.dive + 14 - T.open} layout="none">
        <Audio
          src={staticFile('audio/beat.mp3')}
          loop
          volume={(f) => interpolate(f, [0, 4, T.dive - T.open, T.dive + 14 - T.open], [0, 0.42, 0.42, 0], clamp)}
        />
      </Sequence>
      <Sequence name="Calm outro" from={T.slam} durationInFrames={durationInFrames - T.slam} layout="none">
        <Audio src={staticFile('audio/bed.mp3')} volume={(f) => interpolate(f, [0, 20, durationInFrames - T.slam - 40, durationInFrames - T.slam], [0, 0.22, 0.22, 0], clamp)} />
      </Sequence>

      {/* Sound design. */}
      <Sfx name="Swoop" at={T.swoop + 4} src="audio/whip.mp3" volume={0.5} />
      <Sfx name="Bored glitch" at={146} src="audio/glitch.mp3" volume={0.35} />
      <Sfx name="Pull back" at={T.pullBack + 2} src="audio/whip.mp3" volume={0.45} />
      <Sfx name="Hover" at={T.hover} src="audio/pop.mp3" volume={0.45} />
      <Sfx name="Open drop" at={T.open - 2} src="audio/drop.mp3" volume={0.38} />
      {T.clicks.map((c, i) => (
        <Sfx key={c} name={`Click ${i + 1}`} at={c - 1} src="audio/click.mp3" volume={0.7} length={10} />
      ))}
      <Sfx name="Orbit" at={T.orbit} src="audio/whoosh.mp3" volume={0.45} />
      {T.alerts.map((a, i) => (
        <Sfx key={a} name={`Alert ${i + 1}`} at={a} src="audio/pop.mp3" volume={0.55} />
      ))}
      <Sfx name="Shoulder tap" at={T.tap - 1} src="audio/click.mp3" volume={0.8} length={10} />
      <Sfx name="Carousel in" at={T.carousel} src="audio/whip.mp3" volume={0.5} />
      {[584, 596, 608, 620].map((at, i) => (
        <Sfx key={at} name={`Deck step ${i + 1}`} at={at} src="audio/whip.mp3" volume={0.18} length={20} />
      ))}
      <Sfx name="Fold" at={T.collapse} src="audio/glitch.mp3" volume={0.4} />
      <Sfx name="Fall riser" at={T.dive - 30} src="audio/riser.mp3" volume={0.5} />
      <Sfx name="Bottom drop" at={T.black - 4} src="audio/drop.mp3" volume={0.38} />
      <Sfx name="Icon slam" at={T.slam - 1} src="audio/impact.mp3" volume={0.45} />
    </AbsoluteFill>
  );
};
