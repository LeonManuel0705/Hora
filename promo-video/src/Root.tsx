import { Composition } from "remotion";
import { Promo } from "./Promo";
import { ScrollStory } from "./ScrollStory";
import { HeroVideo } from "./HeroVideo";

const FPS = 60;
const DURATION = 2160; // 36s at 60fps

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="Promo"
        component={Promo}
        durationInFrames={DURATION}
        fps={FPS}
        width={1920}
        height={1080}
      />
      <Composition
        id="PromoVertical"
        component={Promo}
        durationInFrames={DURATION}
        fps={FPS}
        width={1080}
        height={1920}
        defaultProps={{ vertical: true }}
      />
      <Composition
        id="ScrollStory"
        component={ScrollStory}
        durationInFrames={1000}
        fps={30}
        width={1920}
        height={1080}
      />
      <Composition
        id="HeroVideoEN"
        component={HeroVideo}
        durationInFrames={900}
        fps={FPS}
        width={1920}
        height={1080}
        defaultProps={{ lang: "en" as const }}
      />
      <Composition
        id="HeroVideoDE"
        component={HeroVideo}
        durationInFrames={900}
        fps={FPS}
        width={1920}
        height={1080}
        defaultProps={{ lang: "de" as const }}
      />
    </>
  );
};
