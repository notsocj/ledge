import React from 'react';
import {Audio} from '@remotion/media';
import {AbsoluteFill, interpolate, random, Sequence, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {C, clamp, ease} from './lib';
import {Idle, Intro, MenuBar} from './scenes/Opening';
import {ALERT_STARTS, Alerts, Reveal} from './scenes/Reveal';
import {Personas, Tabs} from './scenes/Features';
import {EndCard} from './scenes/EndCard';

const STARS = Array.from({length: 70}, (_, i) => ({
  x: random(`x${i}`) * 1920,
  y: random(`y${i}`) * 620,
  r: 0.6 + random(`r${i}`) * 1.4,
  a: 0.25 + random(`a${i}`) * 0.6,
  depth: 0.3 + random(`d${i}`) * 0.7,
}));

/** The whole film is one MacBook screen at dusk: night above, the horizon's blue glowing up from below. */
const Sky: React.FC = () => {
  const frame = useCurrentFrame();
  const dawn = interpolate(frame, [0, 150], [0, 1], {...clamp, easing: ease.out});
  const swell = interpolate(frame, [270, 300, 420, 885, 1000, 1080], [0.55, 1, 0.75, 0.75, 1, 0.8], clamp);
  return (
    <AbsoluteFill style={{background: C.night}}>
      <AbsoluteFill
        style={{
          opacity: dawn,
          background: `radial-gradient(120% 75% at 50% 112%, rgba(67,104,154,${0.62 * swell}), transparent 62%), linear-gradient(180deg, ${C.night} 0%, ${C.dusk} 55%, #1d3a66 100%)`,
        }}
      />
      {STARS.map((s, i) => (
        <div
          key={i}
          style={{
            position: 'absolute',
            left: s.x,
            top: s.y - frame * 0.12 * s.depth,
            width: s.r * 2,
            height: s.r * 2,
            borderRadius: '50%',
            background: '#fff',
            opacity: s.a * dawn * (0.75 + 0.25 * Math.sin(frame / 18 + i)),
          }}
        />
      ))}
    </AbsoluteFill>
  );
};

/** Fine film grain and a soft vignette, so the flat colours feel photographed rather than drawn. */
const Finish: React.FC = () => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const fadeOut = interpolate(frame, [durationInFrames - 26, durationInFrames - 1], [0, 1], {...clamp, easing: ease.inOut});
  const fadeIn = interpolate(frame, [0, 8], [1, 0], clamp);
  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      <svg width={1920} height={1080} style={{position: 'absolute', inset: 0, opacity: 0.07, mixBlendMode: 'overlay'}}>
        <filter id="grain">
          <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves={2} seed={Math.floor(frame / 2) % 50} />
        </filter>
        <rect width="100%" height="100%" filter="url(#grain)" />
      </svg>
      <AbsoluteFill style={{background: 'radial-gradient(140% 100% at 50% 40%, transparent 55%, rgba(0,0,0,0.55))'}} />
      <AbsoluteFill style={{background: '#000', opacity: Math.max(fadeOut, fadeIn)}} />
    </AbsoluteFill>
  );
};

/** One spoken line, cut from the single voiceover take by its own pauses. */
const Line: React.FC<{at: number; from: number; to: number; name: string}> = ({at, from, to, name}) => {
  const {fps} = useVideoConfig();
  return (
    <Sequence name={name} from={at} durationInFrames={Math.round((to - from) * fps) + 2} layout="none">
      <Audio src={staticFile('audio/voiceover.mp3')} trimBefore={Math.round(from * fps)} trimAfter={Math.round(to * fps)} />
    </Sequence>
  );
};

const Sfx: React.FC<{at: number; src: string; volume: number; name: string}> = ({at, src, volume, name}) => (
  <Sequence name={name} from={at} durationInFrames={70} layout="none">
    <Audio src={staticFile(src)} volume={volume} />
  </Sequence>
);

export const Showreel: React.FC = () => {
  const {fps, durationInFrames} = useVideoConfig();
  return (
    <AbsoluteFill style={{background: C.night}}>
      <Sky />

      <Sequence name="Intro" from={0} durationInFrames={4.5 * fps}>
        <Intro />
      </Sequence>
      <Sequence name="Menu bar" from={4.5 * fps} durationInFrames={9.5 * fps}>
        <MenuBar clockFrom={15} clockTo={58} />
      </Sequence>
      <Sequence name="Sits there" from={4.5 * fps} durationInFrames={4.5 * fps}>
        <Idle />
      </Sequence>
      <Sequence name="Reveal" from={9 * fps} durationInFrames={5 * fps}>
        <Reveal />
      </Sequence>
      <Sequence name="Alerts" from={14 * fps} durationInFrames={7.5 * fps}>
        <Alerts />
      </Sequence>
      <Sequence name="Personas" from={21.5 * fps} durationInFrames={8 * fps}>
        <Personas />
      </Sequence>
      <Sequence name="Tabs" from={29.5 * fps} durationInFrames={6.5 * fps}>
        <Tabs />
      </Sequence>
      <Sequence name="End card" from={36 * fps} durationInFrames={6 * fps}>
        <EndCard />
      </Sequence>

      <Finish />

      {/* Voice: each line placed on its scene. Times are seconds into the take. */}
      <Line name="VO notch" at={30} from={0} to={1.8} />
      <Line name="VO sits there" at={150} from={2.45} to={5.0} />
      <Line name="VO puts it to work" at={300} from={5.65} to={7.3} />
      <Line name="VO quiet" at={438} from={7.8} to={10.12} />
      <Line name="VO what you do" at={660} from={10.66} to={13.62} />
      <Line name="VO hover away" at={900} from={14.1} to={18.32} />
      <Line name="VO end" at={1118} from={18.9} to={21.78} />

      {/* Sound design, all from ElevenLabs. */}
      <Audio
        name="Music bed"
        src={staticFile('audio/bed.mp3')}
        loop
        volume={(f) => interpolate(f, [0, 40, durationInFrames - 50, durationInFrames], [0, 0.2, 0.2, 0], clamp)}
      />
      <Sfx name="Riser" at={222} src="audio/riser.mp3" volume={0.55} />
      <Sfx name="Impact" at={281} src="audio/impact.mp3" volume={0.45} />
      <Sfx name="Whoosh out of reveal" at={398} src="audio/whoosh.mp3" volume={0.35} />
      {ALERT_STARTS.map((s, i) => (
        <Sfx key={s} name={`Pop ${i + 1}`} at={14 * fps + s} src="audio/pop.mp3" volume={0.5} />
      ))}
      <Sfx name="Persona open" at={651} src="audio/pop.mp3" volume={0.4} />
      <Sfx name="Cards in" at={885} src="audio/whoosh.mp3" volume={0.45} />
      <Sfx name="Card 2" at={931} src="audio/whoosh.mp3" volume={0.25} />
      <Sfx name="Card 3" at={957} src="audio/whoosh.mp3" volume={0.25} />
      <Sfx name="Fold into notch" at={994} src="audio/whoosh.mp3" volume={0.5} />
      <Sfx name="Notch pulse" at={1018} src="audio/pop.mp3" volume={0.5} />
      <Sfx name="Icon lands" at={1104} src="audio/impact.mp3" volume={0.3} />
    </AbsoluteFill>
  );
};
