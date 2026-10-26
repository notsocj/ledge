import {Composition} from 'remotion';
import {Showreel} from './Showreel';

export const RemotionRoot: React.FC = () => {
  return (
    <Composition id="LedgeShowreel" component={Showreel} durationInFrames={1260} fps={30} width={1920} height={1080} />
  );
};
