import React from 'react';
import {AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {C, FONT, Island, IslandSize, Letters, NOTCH, Words, clamp, ease, mix, settle} from '../lib';

const TILE = 300;
const TILE_TOP = 250;
// The icon's own notch, from Branding/AppIcon.svg (824pt tile): 560 wide with its shoulders, 168 tall.
const ICON_NOTCH: IslandSize = {width: (560 / 824) * TILE, height: (168 / 824) * TILE, t: (28 / 824) * TILE, b: (36 / 824) * TILE};

/** 0:36 "Ledge. The notch, put to work." The notch leaves the top edge and becomes the app icon. */
export const EndCard: React.FC = () => {
  const f = useCurrentFrame();
  const {fps} = useVideoConfig();
  // The notch travels down and reshapes into the icon's notch...
  const travel = settle(f, fps, 6, 70);
  const size = mix(NOTCH, ICON_NOTCH, travel);
  // ...and the tile unfolds beneath it, growing down from the notch.
  const tile = spring({frame: f - 22, fps, config: {damping: 15, stiffness: 110}});
  const lift = interpolate(f, [22, 60], [0, 1], {...clamp, easing: ease.out});
  return (
    <AbsoluteFill>
      <div
        style={{
          position: 'absolute',
          left: 960 - 420,
          top: TILE_TOP - 140,
          width: 840,
          height: 640,
          borderRadius: '50%',
          background: 'radial-gradient(closest-side, rgba(163,187,220,0.32), transparent)',
          opacity: lift,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 960 - TILE / 2,
          top: TILE_TOP,
          width: TILE,
          height: TILE,
          borderRadius: (186 / 824) * TILE,
          background: C.icon,
          transformOrigin: '50% 0%',
          scale: `${0.25 + 0.75 * tile} ${tile}`,
          opacity: interpolate(tile, [0, 0.2], [0, 1], clamp),
          boxShadow: `0 ${40 * lift}px ${90 * lift}px rgba(0,0,0,0.45)`,
        }}
      />
      <Island size={size} top={TILE_TOP * travel} />
      <AbsoluteFill style={{alignItems: 'center', paddingTop: TILE_TOP + TILE + 56}}>
        <div style={{fontFamily: FONT, fontWeight: 800, fontSize: 170, letterSpacing: '-0.06em', color: C.cream, lineHeight: 1}}>
          <Letters text="Ledge" frame={f} start={38} gap={3} />
        </div>
        <div style={{fontFamily: FONT, fontWeight: 600, fontSize: 68, letterSpacing: '-0.025em', color: C.mist, marginTop: 26}}>
          <Words text="The notch," frame={f} start={68} gap={6} />{' '}
          <Words text="put to work." frame={f} start={97} gap={5} />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
