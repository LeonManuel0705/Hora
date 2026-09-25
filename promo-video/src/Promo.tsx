import React from "react";
import { AbsoluteFill } from "remotion";
import {
  TransitionSeries,
  linearTiming,
} from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { IntroSequence } from "./sequences/IntroSequence";
import { FeaturesSequence } from "./sequences/FeaturesSequence";
import { DashboardSequence } from "./sequences/DashboardSequence";
import { PrivacySequence } from "./sequences/PrivacySequence";
import { OfflineSequence } from "./sequences/OfflineSequence";
import { PlatformSequence } from "./sequences/PlatformSequence";
import { CTASequence } from "./sequences/CTASequence";

interface PromoProps {
  vertical?: boolean;
}

export const Promo: React.FC<PromoProps> = ({
  vertical = false,
}) => {
  const fps = 60;
  const TRANSITION = 30; // 0.5s fade

  const INTRO = 4 * fps;       // 240 — logo + title + tagline
  const DASHBOARD = 4 * fps;   // 240
  const FEATURES = 10 * fps;   // 600 — scroll + pause + "Und vieles mehr"
  const PRIVACY = 4 * fps;     // 240
  const OFFLINE = 4 * fps;     // 240
  const PLATFORM = 5 * fps;    // 300 — device showcase
  const CTA = 8 * fps;         // 480 — hold + fade out + black

  return (
    <AbsoluteFill style={{ backgroundColor: "#000000" }}>
      <TransitionSeries>
        <TransitionSeries.Sequence durationInFrames={INTRO}>
          <IntroSequence />
        </TransitionSeries.Sequence>

        <TransitionSeries.Transition
          presentation={fade()}
          timing={linearTiming({ durationInFrames: TRANSITION })}
        />

        <TransitionSeries.Sequence durationInFrames={DASHBOARD}>
          <DashboardSequence />
        </TransitionSeries.Sequence>

        <TransitionSeries.Transition
          presentation={fade()}
          timing={linearTiming({ durationInFrames: TRANSITION })}
        />

        <TransitionSeries.Sequence durationInFrames={FEATURES}>
          <FeaturesSequence />
        </TransitionSeries.Sequence>

        <TransitionSeries.Transition
          presentation={fade()}
          timing={linearTiming({ durationInFrames: TRANSITION })}
        />

        <TransitionSeries.Sequence durationInFrames={PRIVACY}>
          <PrivacySequence />
        </TransitionSeries.Sequence>

        <TransitionSeries.Transition
          presentation={fade()}
          timing={linearTiming({ durationInFrames: TRANSITION })}
        />

        <TransitionSeries.Sequence durationInFrames={OFFLINE}>
          <OfflineSequence />
        </TransitionSeries.Sequence>

        <TransitionSeries.Transition
          presentation={fade()}
          timing={linearTiming({ durationInFrames: TRANSITION })}
        />

        <TransitionSeries.Sequence durationInFrames={PLATFORM}>
          <PlatformSequence />
        </TransitionSeries.Sequence>

        <TransitionSeries.Transition
          presentation={fade()}
          timing={linearTiming({ durationInFrames: TRANSITION })}
        />

        <TransitionSeries.Sequence durationInFrames={CTA}>
          <CTASequence />
        </TransitionSeries.Sequence>
      </TransitionSeries>
    </AbsoluteFill>
  );
};
