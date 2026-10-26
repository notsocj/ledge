import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {BANNER, C, FONT, Island, IslandSize, Letters, NOTCH, OPEN, Pinned, Words, clamp, ease, islandSpring, mix, settle, slot} from '../lib';

/** A burst of light from the notch when something happens there. */
export const Ripple: React.FC<{frame: number; at: number; strength?: number}> = ({frame, at, strength = 1}) => {
  const p = interpolate(frame, [at, at + 30], [0, 1], {...clamp, easing: ease.out});
  if (frame < at || p >= 1) return null;
  return (
    <div
      style={{
        position: 'absolute',
        left: 960 - 520,
        top: -320,
        width: 1040,
        height: 640,
        borderRadius: '50%',
        background: 'radial-gradient(closest-side, rgba(255,248,239,0.5), rgba(143,178,218,0.22) 45%, transparent)',
        scale: `${0.35 + p * 1.1 * strength}`,
        opacity: (1 - p) * 0.85 * Math.min(1, strength),
      }}
    />
  );
};

/** 0:09 "Ledge puts it to work." The notch squashes, then springs open into the island. */
export const Reveal: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const OPEN_AT = 12;
  // Anticipation: a beat of squash before the release.
  const squash = interpolate(f, [0, OPEN_AT], [0, 1], {...clamp, easing: ease.inOut}) * (f < OPEN_AT ? 1 : 0);
  const open = islandSpring(f, fps, OPEN_AT);
  const close = settle(f, fps, 128, 200);
  const size = mix(mix(NOTCH, OPEN, f < OPEN_AT ? 0 : open), NOTCH, close);
  const content = interpolate(f, [OPEN_AT + 4, OPEN_AT + 20], [0, 1], {...clamp, easing: ease.out}) * (1 - close);
  const shine = interpolate(f, [OPEN_AT + 18, OPEN_AT + 46], [-500, 1700], {...clamp, easing: ease.inOut});
  const bloom = interpolate(f, [OPEN_AT, OPEN_AT + 10, OPEN_AT + 80], [0, 1, 0.35], clamp) * (1 - close);
  const textOut = interpolate(f, [136, 149], [0, 1], {...clamp, easing: ease.inOut});
  return (
    <AbsoluteFill>
      <div
        style={{
          position: 'absolute',
          left: 960 - 900,
          top: -380,
          width: 1800,
          height: 1100,
          borderRadius: '50%',
          background: 'radial-gradient(closest-side, rgba(143,178,218,0.42), transparent)',
          opacity: bloom,
        }}
      />
      <Ripple frame={f} at={OPEN_AT} strength={1.4} />
      <div style={{position: 'absolute', inset: 0, transformOrigin: '960px 0px', scale: `${1 + squash * 0.05} ${1 - squash * 0.12}`}}>
        <Island size={size}>
          <Pinned width={OPEN.width} height={OPEN.height} style={{opacity: content, filter: `blur(${(1 - content) * 10}px)`}}>
            <Img src={staticFile('img/hero-open.png')} style={{width: OPEN.width, height: OPEN.height}} />
          </Pinned>
          <div
            style={{
              position: 'absolute',
              top: 0,
              bottom: 0,
              width: 260,
              left: shine,
              background: 'linear-gradient(100deg, transparent, rgba(255,255,255,0.16), transparent)',
              mixBlendMode: 'screen',
            }}
          />
        </Island>
      </div>
      <AbsoluteFill style={{alignItems: 'center', paddingTop: 520, opacity: 1 - textOut, filter: `blur(${textOut * 12}px)`}}>
        <div style={{fontFamily: FONT, fontWeight: 800, fontSize: 230, letterSpacing: '-0.06em', color: C.cream, lineHeight: 1}}>
          <Letters text="Ledge" frame={f} start={30} gap={3} />
        </div>
        <div style={{fontFamily: FONT, fontWeight: 600, fontSize: 64, letterSpacing: '-0.02em', color: C.mist, marginTop: 18}}>
          <Words text="puts it to work." frame={f} start={44} gap={5} />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

type Alert = {src: string; width: number; caption: string};
const ALERTS: Alert[] = [
  {src: 'img/banner-agent.png', width: 433, caption: 'Claude needs you.'},
  {src: 'img/banner-meeting.png', width: 433, caption: 'Design review in 2 minutes.'},
  {src: 'img/banner-mic.png', width: 377, caption: 'Your mic is muted.'},
  {src: 'img/banner-volume.png', width: 377, caption: 'Volume, without the big square.'},
  {src: 'img/banner-battery.png', width: 377, caption: 'Charging.'},
  {src: 'img/banner-color.png', width: 377, caption: 'A color, copied.'},
];
export const ALERT_STARTS = [72, 102, 129, 153, 174, 195];
const ALERTS_END = 218;

/** 0:14 "Quiet… until something needs you." Alerts fire out of the notch on the beat. */
export const Alerts: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  const index = ALERT_STARTS.reduce((found, s, i) => (f >= s ? i : found), -1);
  let size: IslandSize = NOTCH;
  let shown = 0;
  if (index >= 0) {
    const start = ALERT_STARTS[index];
    const next = ALERT_STARTS[index + 1] ?? ALERTS_END;
    const open = islandSpring(f, fps, start);
    // Each alert tucks back into the notch just before the next one fires.
    const back = interpolate(f, [next - 6, next], [0, 1], {...clamp, easing: ease.inOut});
    const width = ALERTS[index].width * BANNER;
    size = mix(NOTCH, {...NOTCH, width}, open * (1 - back));
    shown = interpolate(open, [0.35, 0.9], [0, 1], clamp) * (1 - back);
  }
  // The camera leans in on the notch while the alerts play.
  const lean = interpolate(f, [60, 90, 205, 225], [0, 1, 1, 0], {...clamp, easing: ease.inOut});
  const lead = interpolate(f, [62, 74], [0, 1], {...clamp, easing: ease.inOut});
  return (
    <AbsoluteFill>
      <div style={{position: 'absolute', inset: 0, transformOrigin: '960px 0px', scale: `${1 + lean * 0.9}`}}>
        {ALERT_STARTS.map((s) => (
          <Ripple key={s} frame={f} at={s} strength={0.7} />
        ))}
        <Island size={size}>
          {index >= 0 && (
            <Pinned width={ALERTS[index].width * BANNER} height={52} style={{opacity: shown}}>
              <Img src={staticFile(ALERTS[index].src)} style={{width: ALERTS[index].width * BANNER, height: 52}} />
            </Pinned>
          )}
        </Island>
      </div>
      {/* The spoken line, then one caption per alert rolling through the same spot. */}
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', textAlign: 'center', paddingTop: 260}}>
        <div style={{opacity: 1 - lead, filter: `blur(${lead * 12}px)`, translate: `0 ${lead * -40}px`}}>
          <div
            style={{
              fontFamily: FONT,
              fontWeight: 600,
              fontSize: 72,
              color: C.mist,
              letterSpacing: `${interpolate(f, [20, 70], [-0.02, 0.18], clamp)}em`,
            }}
          >
            <Words text="Quiet…" frame={f} start={18} />
          </div>
          <div style={{fontFamily: FONT, fontWeight: 700, fontSize: 112, letterSpacing: '-0.04em', color: C.cream, marginTop: 10}}>
            <Words text="until something needs you." frame={f} start={45} gap={5} />
          </div>
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', paddingTop: 300}}>
        <div style={{position: 'relative', height: 140, width: 1700, overflow: 'hidden', lineHeight: '140px'}}>
          {ALERTS.map((alert, i) => {
            const at = slot(f, ALERT_STARTS[i], ALERT_STARTS[i + 1] ?? ALERTS_END + 4);
            if (Math.abs(at) >= 1) return null;
            return (
              <div
                key={i}
                style={{
                  position: 'absolute',
                  inset: 0,
                  textAlign: 'center',
                  fontFamily: FONT,
                  fontWeight: 700,
                  fontSize: 104,
                  letterSpacing: '-0.04em',
                  color: C.cream,
                  translate: `0 ${at * 140}px`,
                  opacity: 1 - Math.abs(at) * 0.6,
                  filter: `blur(${Math.abs(at) * 8}px)`,
                }}
              >
                {alert.caption}
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
