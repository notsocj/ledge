import React from 'react';
import {Easing, interpolate, spring} from 'remotion';

/** The site's palette: night sky, dusk, the horizon's blue, and cream type. */
export const C = {
  night: '#070E1A',
  dusk: '#10203A',
  horizon: '#43689A',
  cream: '#FFF8EF',
  mist: '#AEBFD4',
  icon: '#A3BBDC',
};

export const FONT = '-apple-system, "SF Pro Display", "SF Pro Text", system-ui, sans-serif';
export const W = 1920;

export const ease = {
  out: Easing.bezier(0.23, 1, 0.32, 1),
  inOut: Easing.bezier(0.77, 0, 0.175, 1),
  drawer: Easing.bezier(0.32, 0.72, 0, 1),
};

export const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

/** Island sizes, from the app's own geometry: the closed notch is 185 x 32pt, shown 1.625x. */
export type IslandSize = {width: number; height: number; t: number; b: number};
export const NOTCH: IslandSize = {width: 320, height: 52, t: 10, b: 19.5};
export const OPEN: IslandSize = {width: 1230, height: 394, t: 31, b: 70}; // a 559 x 179pt island at 2.2x
export const BANNER = 52 / 32; // closed-state banners are 32pt tall

export const mix = (a: IslandSize, b: IslandSize, p: number): IslandSize => ({
  width: a.width + (b.width - a.width) * p,
  height: a.height + (b.height - a.height) * p,
  t: a.t + (b.t - a.t) * p,
  b: a.b + (b.b - a.b) * p,
});

/** Apple's island spring: quick, with a little life at the end. */
export const islandSpring = (frame: number, fps: number, delay = 0) =>
  spring({frame: frame - delay, fps, config: {damping: 14, stiffness: 120, mass: 1}});

/** Critically damped: settles without overshoot. */
export const settle = (frame: number, fps: number, delay = 0, stiffness = 140) =>
  spring({frame: frame - delay, fps, config: {damping: 200, stiffness}});

/**
 * The hardware notch's silhouette, the same path the app draws: concave shoulders that flare into
 * the top edge, straight sides, rounded bottom corners.
 */
export const notchPath = (w: number, h: number, t: number, b: number) => {
  const bb = Math.max(0, Math.min(b, h - t, (w - 2 * t) / 2));
  return [
    `M 0 0`,
    `Q ${t} 0 ${t} ${t}`,
    `L ${t} ${h - bb}`,
    `Q ${t} ${h} ${t + bb} ${h}`,
    `L ${w - t - bb} ${h}`,
    `Q ${w - t} ${h} ${w - t} ${h - bb}`,
    `L ${w - t} ${t}`,
    `Q ${w - t} 0 ${w} 0`,
    `Z`,
  ].join(' ');
};

/** The island: black, notch-shaped, hanging from the top edge, with whatever it shows clipped inside. */
export const Island: React.FC<{
  size: IslandSize;
  top?: number;
  centerX?: number;
  children?: React.ReactNode;
  style?: React.CSSProperties;
}> = ({size, top = 0, centerX = W / 2, children, style}) => {
  const {width, height, t, b} = size;
  return (
    <div style={{position: 'absolute', left: centerX - width / 2, top, width, height, ...style}}>
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: '#000',
          clipPath: `path('${notchPath(width, height, t, b)}')`,
          overflow: 'hidden',
        }}
      >
        {children}
      </div>
    </div>
  );
};

/** Content pinned to the island's top centre, so the island's growth reveals it instead of zooming it. */
export const Pinned: React.FC<{width: number; height: number; children: React.ReactNode; style?: React.CSSProperties}> = ({
  width,
  height,
  children,
  style,
}) => (
  <div style={{position: 'absolute', top: 0, left: '50%', width, height, marginLeft: -width / 2, ...style}}>{children}</div>
);

/** One word at a time, each rising out of a soft blur: the house style for every line of type. */
export const Words: React.FC<{
  text: string;
  frame: number;
  start: number;
  gap?: number;
  style?: React.CSSProperties;
  out?: number;
}> = ({text, frame, start, gap = 4, style, out}) => {
  const words = text.split(' ');
  return (
    <span style={{display: 'inline-block', whiteSpace: 'nowrap', ...style}}>
      {words.map((word, i) => {
        const begin = start + i * gap;
        const p = interpolate(frame, [begin, begin + 16], [0, 1], {...clamp, easing: ease.out});
        const leave = out === undefined ? 0 : interpolate(frame, [out + i * 2, out + i * 2 + 12], [0, 1], {...clamp, easing: ease.inOut});
        return (
          <span
            key={i}
            style={{
              display: 'inline-block',
              marginRight: i < words.length - 1 ? '0.26em' : 0,
              opacity: p * (1 - leave),
              translate: `0 ${(1 - p) * 0.45 - leave * 0.35}em`,
              filter: `blur(${(1 - p) * 14 + leave * 10}px)`,
            }}
          >
            {word}
          </span>
        );
      })}
    </span>
  );
};

/**
 * Where a line sits in a rolling slot: 0 at rest, 1 a slot below (coming in), -1 a slot above (gone).
 * Lines change on the same frames with the same curve, so neighbours never overlap.
 */
export const slot = (frame: number, start: number, next: number | undefined, length = 14) => {
  const enter = interpolate(frame, [start, start + length], [1, 0], {...clamp, easing: ease.drawer});
  const exit = next === undefined ? 0 : interpolate(frame, [next, next + length], [0, -1], {...clamp, easing: ease.drawer});
  return enter + exit;
};

/** Letters assembling from wide tracking into place. */
export const Letters: React.FC<{text: string; frame: number; start: number; gap?: number; style?: React.CSSProperties}> = ({
  text,
  frame,
  start,
  gap = 2,
  style,
}) => (
  <span style={{display: 'inline-block', whiteSpace: 'pre', ...style}}>
    {text.split('').map((ch, i) => {
      const p = interpolate(frame, [start + i * gap, start + i * gap + 18], [0, 1], {...clamp, easing: ease.out});
      return (
        <span
          key={i}
          style={{
            display: 'inline-block',
            opacity: p,
            translate: `${(1 - p) * (i - text.length / 2) * 0.12}em ${(1 - p) * 0.5}em`,
            filter: `blur(${(1 - p) * 12}px)`,
          }}
        >
          {ch}
        </span>
      );
    })}
  </span>
);
