import React from "react";
import {
  useCurrentFrame,
  interpolate,
  staticFile,
  Img,
} from "remotion";
import { COLORS, GRADIENTS, FONTS } from "../theme";
import { BRAND_NAME } from "../brand";

export const IntroSequence: React.FC = () => {
  const frame = useCurrentFrame();

  const logoOpacity = interpolate(frame, [30, 80], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const logoScale = interpolate(frame, [30, 80], [0.8, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const titleOpacity = interpolate(frame, [60, 100], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const titleY = interpolate(frame, [60, 100], [20, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const lineWidth = interpolate(frame, [100, 160], [0, 260], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const lineOpacity = interpolate(frame, [100, 120], [0, 0.5], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const taglineOpacity = interpolate(frame, [130, 170], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const taglineY = interpolate(frame, [130, 170], [12, 0], {
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
          style={{ width: 140, height: 140 }}
        />
      </div>

      {/* Title — brand gradient */}
      <div
        style={{
          opacity: titleOpacity,
          transform: `translateY(${titleY}px)`,
          fontSize: 130,
          fontFamily: FONTS.display,
          fontWeight: 700,
          letterSpacing: -4,
          background: GRADIENTS.brand,
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
        }}
      >
        {BRAND_NAME}
      </div>

      {/* Thin line */}
      <div
        style={{
          width: lineWidth,
          height: 1,
          background: GRADIENTS.brand,
          marginTop: 36,
          marginBottom: 36,
          opacity: lineOpacity,
        }}
      />

      {/* Tagline */}
      <div
        style={{
          opacity: taglineOpacity,
          transform: `translateY(${taglineY}px)`,
          fontSize: 36,
          fontFamily: FONTS.body,
          fontWeight: 400,
          background: "linear-gradient(180deg, #b0b0b5 0%, #6a6a6f 100%)",
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
          letterSpacing: 1,
        }}
      >
        Dein Leben, verbunden.
      </div>
    </div>
  );
};
