import {Easing} from 'remotion';
import {ease} from '../lib';

/** The whole film is one take on a 1920 x 1200 MacBook screen. These are its beats, in frames at 30 fps. */
export const T = {
  swoop: 10, // the cursor leaves its spot
  idle: 58, // ...and arrives at the notch, which is doing nothing
  pullBack: 172, // "Watch this."
  glide: 205, // the cursor heads for the notch
  hover: 228,
  open: 236,
  clicks: [288, 321, 351, 389], // music, week, limits, servers
  leave: 405,
  orbit: 418,
  close: 425,
  alerts: [470, 512, 538], // Claude waiting, a meeting, the mic
  tap: 503, // "...on the shoulder"
  carousel: 562,
  collapse: 632,
  dive: 640,
  black: 668,
  slam: 678,
  end: 870,
};

/** A tab icon's x in the island image (pt), turned into screen coordinates. The island is shown at 2.2x. */
export const tabX = (pt: number) => 960 - 615 + pt * 2.2;
export const TAB_Y = 35;

type Ease = (t: number) => number;
export type Key = [frame: number, value: number, easing?: Ease];

/** Piecewise keyframes, each segment with its own curve (ease-in-out unless given). */
export const keys = (f: number, ks: Key[]) => {
  if (f <= ks[0][0]) return ks[0][1];
  for (let i = 0; i < ks.length - 1; i++) {
    const [a, va] = ks[i];
    const [b, vb, e] = ks[i + 1];
    if (f <= b) return va + (vb - va) * (e ?? ease.inOut)((f - a) / (b - a));
  }
  return ks[ks.length - 1][1];
};

export const drawer = ease.drawer;
const fall = Easing.in(Easing.exp); // falling into the notch accelerates

// Where the cursor goes: up to the notch, a restless figure-eight, onto the notch, then tab to tab.
const clickX = [tabX(152), tabX(31), tabX(102), tabX(528)];
export const cursorAt = (f: number) => {
  let x = keys(f, [
    [T.swoop, 1010],
    [T.idle - 6, 1010, drawer],
    [T.pullBack, 1010],
    [T.glide, 1290, drawer],
    [T.hover, 978, drawer],
    [T.clicks[0] - 2, clickX[0], drawer],
    [T.clicks[1] - 2, clickX[1], drawer],
    [T.clicks[2] - 2, clickX[2], drawer],
    [T.clicks[3] - 2, clickX[3], drawer],
    [T.leave + 18, 1420, drawer],
  ]);
  let y = keys(f, [
    [T.swoop, 960],
    [T.idle - 6, 118, drawer],
    [T.pullBack, 118],
    [T.glide, 330, drawer],
    [T.hover, 30, drawer],
    [T.open + 6, 30],
    [T.clicks[0] - 2, TAB_Y, drawer],
    [T.clicks[3] - 2, TAB_Y],
    [T.leave + 18, 640, drawer],
  ]);
  // Impatient loops around the idle notch.
  if (f > T.idle && f < T.pullBack) {
    const t = (f - T.idle) / (T.pullBack - T.idle);
    const fade = Math.sin(Math.PI * t);
    x += fade * 190 * Math.sin(t * Math.PI * 4);
    y += fade * 38 * Math.sin(t * Math.PI * 8);
  }
  return {x, y};
};

/** What the camera aims at before it's smoothed: a framed point, partly pulled toward the cursor. */
const aim = (f: number) => {
  const c = cursorAt(f);
  const follow = keys(f, [
    [0, 1],
    [T.idle, 1],
    [T.idle + 20, 0.25],
    [T.pullBack, 0.25],
    [T.pullBack + 20, 0.1],
    [T.glide, 0.45],
    [T.open, 0.2],
    [T.clicks[0] - 20, 0.55],
    [T.leave, 0.55],
    [T.orbit, 0],
  ]);
  // During the tabs the camera holds its height, so the captions never sit on the island.
  const followY = Math.min(follow, keys(f, [[T.open, 1], [T.clicks[0] - 20, 0], [T.leave, 0], [T.leave + 10, 1]]));
  const fx = keys(f, [[0, 960], [T.end, 960]]);
  const fy = keys(f, [
    [0, 960],
    [T.idle, 150],
    [T.pullBack, 150],
    [T.pullBack + 24, 560],
    [T.glide + 10, 300],
    [T.open + 10, 250],
    [T.orbit, 250],
    [T.orbit + 22, 640],
    [T.alerts[0] - 6, 640],
    [T.alerts[0] + 6, 90, drawer],
    [T.alerts[0] + 30, 420],
    [T.alerts[1] - 4, 420],
    [T.alerts[1] + 6, 90, drawer],
    [T.alerts[2] + 18, 600],
    [T.dive - 8, 120],
    [T.dive, 26],
  ]);
  return {x: fx + (c.x - fx) * follow, y: fy + (c.y - fy) * followY};
};

/** Zoom: wide shots, punch-ins on every click, and the fall into the notch. */
const zoomAt = (f: number) => {
  const punches = T.clicks.reduce((sum, at) => sum + 0.4 * Math.exp(-(((f - at) / 7) ** 2)), 0);
  return (
    keys(f, [
      [0, 4.2],
      [T.idle - 6, 2.3, drawer],
      [T.pullBack, 2.6],
      [T.pullBack + 24, 1.05, drawer],
      [T.glide + 14, 1.9],
      [T.open, 2.1],
      [T.open + 12, 1.42, drawer],
      [T.leave, 1.42],
      [T.orbit + 26, 0.66, drawer],
      [T.alerts[0] - 6, 0.66],
      [T.alerts[0] + 8, 2.1, drawer],
      [T.alerts[0] + 34, 1.0],
      [T.alerts[1] - 4, 1.0],
      [T.alerts[1] + 8, 2.0, drawer],
      [T.alerts[2] + 18, 0.85],
      [T.dive - 8, 1.1],
      [T.dive, 1.4],
      [T.black, 60, fall],
    ]) + punches
  );
};

/** Moments that shake the camera: [frame, strength]. */
const SHAKES: [number, number][] = [
  [T.open, 14],
  [T.alerts[0], 7],
  [T.tap, 16],
  [T.alerts[1], 5],
  [T.alerts[2], 5],
];

export type Cam = {x: number; y: number; z: number; rot: number; blurX: number; blurY: number};

/**
 * The camera chases its aim on a spring, so it lags, overshoots a touch and banks into turns like a
 * hand-held operator following the cursor. Simulated once for the whole film; every frame reads it.
 */
const simulate = (): Cam[] => {
  const out: Cam[] = [];
  let a = aim(0);
  let x = a.x, y = a.y, vx = 0, vy = 0;
  let z = zoomAt(0), vz = 0;
  for (let f = 0; f <= T.end; f++) {
    a = aim(f);
    const tz = zoomAt(f);
    if (f >= T.dive) {
      // Falling into the notch is exact, not chased.
      vx = a.x - x; vy = a.y - y; x = a.x; y = a.y; vz = 0; z = tz;
    } else {
      vx += (a.x - x) * 0.12 - vx * 0.42;
      vy += (a.y - y) * 0.12 - vy * 0.42;
      vz += (tz - z) * 0.2 - vz * 0.55;
      x += vx; y += vy; z += vz;
    }
    let sx = 0, sy = 0, sr = 0;
    for (const [at, amp] of SHAKES) {
      if (f < at) continue;
      const k = amp * Math.exp(-(f - at) / 5);
      sx += k * Math.sin((f - at) * 2.7);
      sy += k * Math.cos((f - at) * 3.3);
      sr += k * 0.06 * Math.sin((f - at) * 2.1);
    }
    const speedX = vx * z, speedY = vy * z; // how fast things move on screen
    out.push({
      x: x + sx / z,
      y: y + sy / z,
      z,
      rot: Math.max(-6, Math.min(6, -speedX * 0.035)) + sr,
      blurX: Math.min(26, Math.abs(speedX) * 0.22),
      blurY: Math.min(26, Math.abs(speedY) * 0.22),
    });
  }
  return out;
};

export const CAMERA = simulate();
export const camAt = (f: number) => CAMERA[Math.max(0, Math.min(CAMERA.length - 1, Math.round(f)))];

/** A point on the screen plane, as the camera sees it. */
export const toScreen = (f: number, p: {x: number; y: number}) => {
  const c = camAt(f);
  const r = (c.rot * Math.PI) / 180;
  const dx = (p.x - c.x) * c.z, dy = (p.y - c.y) * c.z;
  return {x: 960 + dx * Math.cos(r) - dy * Math.sin(r), y: 540 + dx * Math.sin(r) + dy * Math.cos(r)};
};
