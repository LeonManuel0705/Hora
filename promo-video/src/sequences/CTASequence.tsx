import React from "react";
import {
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  staticFile,
  Img,
} from "remotion";
import { COLORS, FONTS, GRADIENTS } from "../theme";
import { BRAND_WEBSITE } from "../brand";

export const CTASequence: React.FC = () => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();

  // Fade-out: 2.5s fade, then 0.5s pure black
  const fadeOutStart = durationInFrames - 180;
  const fadeOutEnd = durationInFrames - 30;

  const masterOpacity = interpolate(
    frame,
    [fadeOutStart, fadeOutEnd],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  const logoOpacity = interpolate(frame, [0, 50], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const logoScale = interpolate(frame, [0, 50], [0.85, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const line1Opacity = interpolate(frame, [20, 60], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const line1Y = interpolate(frame, [20, 60], [20, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const line2Opacity = interpolate(frame, [40, 80], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const line2Y = interpolate(frame, [40, 80], [20, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const urlOpacity = interpolate(frame, [110, 150], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const lineWidth = interpolate(frame, [140, 180], [0, 160], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const availableOpacity = interpolate(frame, [160, 190], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const platformOpacity = interpolate(frame, [190, 230], [0, 0.7], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        background: COLORS.black,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <div
        style={{
          opacity: masterOpacity,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
        }}
      >
        {/* Logo */}
        <div
          style={{
            opacity: logoOpacity,
            transform: `scale(${logoScale})`,
            marginBottom: 50,
          }}
        >
          <Img
            src={staticFile("logo.png")}
            style={{ width: 110, height: 110 }}
          />
        </div>

        {/* Line 1 */}
        <div
          style={{
            opacity: line1Opacity,
            transform: `translateY(${line1Y}px)`,
            fontSize: 78,
            fontFamily: FONTS.display,
            fontWeight: 600,
            letterSpacing: -3,
            lineHeight: 1.1,
            background: "linear-gradient(180deg, #ffffff 0%, #808085 100%)",
            WebkitBackgroundClip: "text",
            WebkitTextFillColor: "transparent",
            textAlign: "center",
            marginBottom: 4,
          }}
        >
          Dein Leben verdient
        </div>

        {/* Line 2 */}
        <div
          style={{
            opacity: line2Opacity,
            transform: `translateY(${line2Y}px)`,
            fontSize: 78,
            fontFamily: FONTS.display,
            fontWeight: 600,
            letterSpacing: -3,
            lineHeight: 1.1,
            background: GRADIENTS.brand,
            WebkitBackgroundClip: "text",
            WebkitTextFillColor: "transparent",
            textAlign: "center",
          }}
        >
          bessere Tools.
        </div>

        {/* URL */}
        <div
          style={{
            opacity: urlOpacity,
            marginTop: 60,
            fontSize: 26,
            fontFamily: FONTS.body,
            fontWeight: 400,
            background: "linear-gradient(180deg, #ffffff 0%, #909095 100%)",
            WebkitBackgroundClip: "text",
            WebkitTextFillColor: "transparent",
            letterSpacing: 1.5,
          }}
        >
          {new URL(BRAND_WEBSITE).host}
        </div>

        {/* Thin line */}
        <div
          style={{
            width: lineWidth,
            height: 1,
            background: GRADIENTS.brand,
            marginTop: 28,
            opacity: 0.4,
          }}
        />

        {/* Available now */}
        <div
          style={{
            opacity: availableOpacity,
            marginTop: 24,
            fontSize: 17,
            fontFamily: FONTS.body,
            fontWeight: 400,
            color: COLORS.gray,
            letterSpacing: 4,
            textTransform: "uppercase",
          }}
        >
          Jetzt kostenlos verfügbar
        </div>

        {/* Platform labels */}
        <div
          style={{
            opacity: platformOpacity,
            marginTop: 30,
            display: "flex",
            alignItems: "center",
            gap: 36,
          }}
        >
          {["macOS", "Windows", "Linux", "iOS", "Android"].map((p) => (
            <div
              key={p}
              style={{
                fontSize: 14,
                fontFamily: FONTS.body,
                color: COLORS.gray,
                letterSpacing: 2,
                textTransform: "uppercase",
              }}
            >
              {p}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
