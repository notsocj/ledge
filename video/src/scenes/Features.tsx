import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {C, FONT, Island, NOTCH, OPEN, Pinned, Words, clamp, ease, islandSpring, mix, settle, slot} from '../lib';
import {Ripple} from './Reveal';

const PERSONAS = [
  {name: 'Developer', src: 'img/home-developer.png', h: 179},
  {name: 'Designer', src: 'img/home-designer.png', h: 179},
  {name: 'Creator', src: 'img/home-creator.png', h: 164},
  {name: 'Student', src: 'img/home-student.png', h: 179},
  {name: 'Professional', src: 'img/home-professional.png', h: 179},
  {name: 'Essentials', src: 'img/home-essentials.png', h: 179},
];
const SWITCHES = [0, 58, 80, 102, 124, 146]; // local frames: each persona takes over

/** 0:21 "Tell it what you do, and it arranges itself around you." One island, six lives. */
export const Personas: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const open = islandSpring(f, fps, 6);
  const close = settle(f, fps, 222, 200);
  const current = SWITCHES.reduce((found, s, i) => (f >= s ? i : found), 0);
  // The island's height follows each Home with a spring, like the real one measuring itself.
  const heightSpring = settle(f, fps, SWITCHES[current], 220);
  const prevH = PERSONAS[Math.max(0, current - 1)].h * 2.2;
  const height = prevH + (PERSONAS[current].h * 2.2 - prevH) * heightSpring;
  const target = {...OPEN, height};
  const size = mix(mix(NOTCH, target, open), NOTCH, close);
  const captionOut = interpolate(f, [216, 236], [0, 1], {...clamp, easing: ease.inOut});
  return (
    <AbsoluteFill>
      <Ripple frame={f} at={6} strength={0.9} />
      <Island size={size}>
        {PERSONAS.map((p, i) => {
          const start = SWITCHES[i];
          const end = SWITCHES[i + 1] ?? 10_000;
          const enter = i === 0 ? interpolate(f, [10, 24], [0, 1], clamp) : interpolate(f, [start, start + 10], [0, 1], {...clamp, easing: ease.out});
          const exit = interpolate(f, [end, end + 8], [0, 1], clamp);
          const vis = enter * (1 - exit) * (1 - close);
          if (vis <= 0) return null;
          return (
            <Pinned key={p.name} width={OPEN.width} height={p.h * 2.2} style={{opacity: vis, filter: `blur(${(1 - enter) * 10 + exit * 6}px)`, scale: `${0.985 + 0.015 * enter}`}}>
              <Img src={staticFile(p.src)} style={{width: OPEN.width, height: p.h * 2.2}} />
            </Pinned>
          );
        })}
      </Island>
      {/* A slot of persona names: each new one rolls up into place as the island changes. */}
      <AbsoluteFill style={{alignItems: 'center', paddingTop: 520}}>
        <div style={{position: 'relative', width: 1700, height: 230, overflow: 'hidden', opacity: 1 - captionOut}}>
          {PERSONAS.map((p, i) => {
            const at = slot(f, SWITCHES[i] + (i === 0 ? 24 : 0), SWITCHES[i + 1]);
            if (Math.abs(at) >= 1) return null;
            return (
              <div
                key={p.name}
                style={{
                  position: 'absolute',
                  inset: 0,
                  textAlign: 'center',
                  fontFamily: FONT,
                  fontWeight: 800,
                  fontSize: 200,
                  letterSpacing: '-0.06em',
                  lineHeight: '230px',
                  color: C.cream,
                  translate: `0 ${at * 230}px`,
                  filter: `blur(${Math.abs(at) * 10}px)`,
                }}
              >
                {p.name}
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{alignItems: 'center', paddingTop: 830, opacity: 1 - captionOut}}>
        <div style={{fontFamily: FONT, fontWeight: 600, fontSize: 56, letterSpacing: '-0.015em', color: C.mist}}>
          <Words text="Tell it what you do," frame={f} start={16} gap={4} />{' '}
          <Words text="and it arranges itself around you." frame={f} start={52} gap={4} />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

const CARDS = [
  {src: 'img/tab-music.png', h: 181, label: 'Your music.'},
  {src: 'img/tab-stats.png', h: 152, label: 'Your limits.'},
  {src: 'img/tab-ports.png', h: 173, label: 'Your servers.'},
  {src: 'img/tab-timer.png', h: 152, label: ''},
];
const CUES = [16, 46, 72]; // local frames where each line is spoken
const HOVER = 109; // "One hover away."
const CARD_SCALE = 1.7;

/** 0:29 "Your music. Your limits. Your servers. One hover away." A cover flow that folds into the notch. */
export const Tabs: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  // The active card, as a smooth value: each cue springs it one place along.
  const active = CUES.slice(1).reduce((sum, cue) => sum + settle(f, fps, cue, 160), 0);
  const arrive = settle(f, fps, 0, 90);
  const notchPulse = interpolate(f, [HOVER + 22, HOVER + 28, HOVER + 40], [1, 1.12, 1], clamp);
  const hoverText = interpolate(f, [HOVER + 6, HOVER + 22], [0, 1], {...clamp, easing: ease.out});
  const hoverOut = interpolate(f, [184, 195], [0, 1], {...clamp, easing: ease.inOut});
  return (
    <AbsoluteFill>
      <Ripple frame={f} at={HOVER + 24} strength={1.2} />
      <div style={{position: 'absolute', inset: 0, transformOrigin: '960px 0px', scale: `${notchPulse}`}}>
        <Island size={NOTCH} />
      </div>
      <AbsoluteFill style={{perspective: 2000, perspectiveOrigin: '50% 40%'}}>
        {CARDS.map((card, i) => {
          const pos = i - active;
          const away = Math.min(Math.abs(pos), 2.2);
          // Folding away into the notch, the outer cards first.
          const fold = interpolate(f, [HOVER + Math.abs(pos) * 3, HOVER + 26 + Math.abs(pos) * 3], [0, 1], {...clamp, easing: ease.inOut});
          const w = 559 * CARD_SCALE, h = card.h * CARD_SCALE;
          const restX = pos * 760, restY = 470 - h / 2;
          const x = restX * (1 - fold);
          const y = restY * (1 - fold) + 4 * fold + (1 - arrive) * 260;
          return (
            <div
              key={card.src}
              style={{
                position: 'absolute',
                left: 960 - w / 2,
                top: 0,
                width: w,
                height: h,
                translate: `${x}px ${y}px ${(1 - arrive) * -900 - away * 120}px`,
                rotate: `0 1 0 ${-pos * 34 * (1 - fold)}deg`,
                scale: `${(1 - away * 0.12) * (1 - fold * 0.86)}`,
                transformOrigin: '50% 0%',
                opacity: (1 - away * 0.32) * (1 - fold) * arrive,
                zIndex: 100 - Math.round(away * 10),
                filter: `blur(${away * 2.5 + fold * 6}px) drop-shadow(0 40px 60px rgba(0,0,0,0.5))`,
              }}
            >
              <Img src={staticFile(card.src)} style={{width: w, height: h}} />
            </div>
          );
        })}
      </AbsoluteFill>
      {/* What's said, one line per card, rolling through one slot. */}
      <AbsoluteFill style={{alignItems: 'center', paddingTop: 790}}>
        <div style={{position: 'relative', width: 1600, height: 150, overflow: 'hidden'}}>
          {CARDS.slice(0, 3).map((card, i) => {
            const at = slot(f, CUES[i], CUES[i + 1] ?? HOVER);
            if (Math.abs(at) >= 1) return null;
            return (
              <div
                key={card.label}
                style={{
                  position: 'absolute',
                  inset: 0,
                  textAlign: 'center',
                  fontFamily: FONT,
                  fontWeight: 800,
                  fontSize: 130,
                  letterSpacing: '-0.05em',
                  lineHeight: '150px',
                  color: C.cream,
                  translate: `0 ${at * 150}px`,
                  filter: `blur(${Math.abs(at) * 8}px)`,
                }}
              >
                {card.label}
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
      <AbsoluteFill
        style={{
          justifyContent: 'center',
          alignItems: 'center',
          paddingTop: 80,
          opacity: hoverText * (1 - hoverOut),
          filter: `blur(${(1 - hoverText) * 14 + hoverOut * 12}px)`,
          scale: `${0.94 + 0.06 * hoverText}`,
        }}
      >
        <div style={{fontFamily: FONT, fontWeight: 800, fontSize: 168, letterSpacing: '-0.06em', color: C.cream}}>One hover away.</div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
