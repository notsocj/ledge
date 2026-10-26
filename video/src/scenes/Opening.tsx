import React from 'react';
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {C, FONT, Island, NOTCH, Words, clamp, ease, islandSpring} from '../lib';

const headline: React.CSSProperties = {
  fontFamily: FONT,
  fontWeight: 700,
  fontSize: 132,
  letterSpacing: '-0.045em',
  lineHeight: 1.02,
  color: C.cream,
};

/** 0:00 "Every MacBook has a notch." The notch drops in from the top edge and a line points at it. */
export const Intro: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const drop = islandSpring(f, fps, 6);
  const glow = interpolate(f, [10, 40, 130], [0, 1, 0.55], clamp);
  // A leader line draws from the word up to the notch, then pulls back.
  const draw = interpolate(f, [62, 88], [0, 1], {...clamp, easing: ease.out});
  const retract = interpolate(f, [104, 122], [0, 1], {...clamp, easing: ease.inOut});
  const length = 330;
  return (
    <AbsoluteFill>
      <div
        style={{
          position: 'absolute',
          left: 960 - 420,
          top: -260,
          width: 840,
          height: 520,
          borderRadius: '50%',
          background: 'radial-gradient(closest-side, rgba(143,178,218,0.28), transparent)',
          opacity: glow,
        }}
      />
      <Island size={NOTCH} style={{translate: `0 ${(1 - drop) * -70}px`}} />
      <svg width={1920} height={1080} style={{position: 'absolute', inset: 0}}>
        <line
          x1={960}
          y1={70 + length}
          x2={960}
          y2={70}
          stroke={C.mist}
          strokeWidth={2}
          strokeLinecap="round"
          strokeDasharray={length}
          strokeDashoffset={length * (1 - draw) - length * retract}
          opacity={0.7}
        />
        <circle cx={960} cy={66} r={5} fill={C.cream} opacity={draw * (1 - retract)} />
      </svg>
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', textAlign: 'center', paddingTop: 140}}>
        <div style={headline}>
          <Words text="Every MacBook" frame={f} start={28} gap={7} out={110} />
          <br />
          <Words text="has a notch." frame={f} start={44} gap={5} out={112} />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/** The macOS menu bar, sliding down when the screen comes alive, with a clock that can fast-forward. */
export const MenuBar: React.FC<{clockFrom: number; clockTo: number}> = ({clockFrom, clockTo}) => {
  const f = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const enter = spring({frame: f, fps, config: {damping: 200, stiffness: 120}});
  const leave = interpolate(f, [durationInFrames - 20, durationInFrames], [0, 1], {...clamp, easing: ease.inOut});
  const dim = interpolate(f, [130, 150], [1, 0.45], clamp);
  // 9:41 AM racing to 5:07 PM: "most of the time".
  const minutes = Math.round(interpolate(f, [clockFrom, clockTo], [9 * 60 + 41, 17 * 60 + 7], {...clamp, easing: ease.inOut}));
  const h = Math.floor(minutes / 60), m = minutes % 60;
  const clock = `Mon ${((h + 11) % 12) + 1}:${String(m).padStart(2, '0')} ${h >= 12 ? 'PM' : 'AM'}`;
  const item: React.CSSProperties = {fontFamily: FONT, fontSize: 26, fontWeight: 600, color: 'rgba(255,255,255,0.92)'};
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
        padding: '0 34px',
        background: 'rgba(10,18,32,0.42)',
        backdropFilter: 'blur(24px)',
        translate: `0 ${(1 - enter) * -60 - leave * 60}px`,
        opacity: dim * (1 - leave),
      }}
    >
      <div style={{display: 'flex', gap: 40, ...item}}>
        <span style={{fontWeight: 700}}>Finder</span>
        <span>File</span>
        <span>Edit</span>
        <span>View</span>
        <span>Go</span>
        <span>Window</span>
      </div>
      <div style={{display: 'flex', gap: 34, alignItems: 'center', ...item}}>
        <span style={{opacity: 0.85}}>100%</span>
        <span style={{fontVariantNumeric: 'tabular-nums'}}>{clock}</span>
      </div>
    </div>
  );
};

/** 0:05 "Most of the time… it just sits there." The last words slump like they've given up. */
export const Idle: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const out = interpolate(f, [112, 128], [0, 1], {...clamp, easing: ease.inOut});
  const slumpText = 'sits there.';
  return (
    <AbsoluteFill>
      <Island size={NOTCH} />
      <AbsoluteFill
        style={{
          justifyContent: 'center',
          alignItems: 'center',
          textAlign: 'center',
          paddingTop: 120,
          opacity: 1 - out,
          filter: `blur(${out * 12}px)`,
        }}
      >
        <div style={{fontFamily: FONT, fontWeight: 600, fontSize: 64, letterSpacing: '-0.02em', color: C.mist, marginBottom: 18}}>
          <Words text="Most of the time…" frame={f} start={16} gap={6} />
        </div>
        <div style={{fontFamily: FONT, fontWeight: 700, fontSize: 132, letterSpacing: '-0.045em', color: C.cream}}>
          <Words text="it just" frame={f} start={60} gap={6} />
          <span style={{display: 'inline-block', width: '0.26em'}} />
          {slumpText.split('').map((ch, i) => {
            const appear = interpolate(f, [70 + i, 82 + i], [0, 1], {...clamp, easing: ease.out});
            // Each letter sags under its own weight and bounces to rest.
            const sag = spring({frame: f - (84 + i * 2), fps, config: {damping: 7, stiffness: 90, mass: 0.9}});
            const tilt = [7, -5, 9, -4, 0, 6, -8, 5, -6, 8, 3][i] ?? 0;
            return (
              <span
                key={i}
                style={{
                  display: 'inline-block',
                  whiteSpace: 'pre',
                  opacity: appear,
                  filter: `blur(${(1 - appear) * 12}px)`,
                  translate: `0 ${(1 - appear) * 50 + sag * (30 + (i % 3) * 12)}px`,
                  rotate: `${sag * tilt * 1.8}deg`,
                  transformOrigin: 'bottom center',
                }}
              >
                {ch}
              </span>
            );
          })}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
