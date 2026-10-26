import {Composition} from 'remotion';
import {Showreel} from './Showreel';
import {OneTake} from './onetake/OneTake';

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition id="LedgeShowreel" component={Showreel} durationInFrames={1260} fps={30} width={1920} height={1080} />
      <Composition id="LedgeOneTake" component={OneTake} durationInFrames={870} fps={30} width={1920} height={1080} />
    </>
  );
};
