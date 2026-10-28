import {Composition} from 'remotion';
import {Showreel} from './Showreel';
import {OneTake} from './onetake/OneTake';
import {LOOP_FRAMES, MOMENTS_HEIGHT, MOMENTS_WIDTH, PERSONAS_HEIGHT, PERSONAS_WIDTH, ReadmeLoop, ReadmeMoments, ReadmePersonas} from './readme/Readme';

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition id="LedgeShowreel" component={Showreel} durationInFrames={1260} fps={30} width={1920} height={1080} />
      <Composition id="LedgeOneTake" component={OneTake} durationInFrames={870} fps={30} width={1920} height={1080} />
      <Composition id="ReadmeLoop" component={ReadmeLoop} durationInFrames={LOOP_FRAMES} fps={30} width={1280} height={500} />
      <Composition id="ReadmeMoments" component={ReadmeMoments} durationInFrames={1} fps={30} width={MOMENTS_WIDTH} height={MOMENTS_HEIGHT} />
      <Composition id="ReadmePersonas" component={ReadmePersonas} durationInFrames={1} fps={30} width={PERSONAS_WIDTH} height={PERSONAS_HEIGHT} />
    </>
  );
};
