import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  staticFile,
  Img,
} from "remotion";
import { COLORS, FONTS, GRADIENTS } from "./theme";
import { BRAND_WEBSITE } from "./brand";
import { FeatureIcon } from "./components/FeatureIcon";

// ==================== DATA ====================

const FEATURES = [
  { title: "Kalender", icon: "calendar" },
  { title: "E-Mail", icon: "email" },
  { title: "Aufgaben", icon: "tasks" },
  { title: "Schule", icon: "school" },
  { title: "Training", icon: "training" },
  { title: "Notizen", icon: "notes" },
  { title: "Pomodoro", icon: "pomodoro" },
  { title: "Projekte", icon: "projects" },
  { title: "Transport", icon: "transit" },
  { title: "Lesezeichen", icon: "bookmarks" },
  { title: "Assistent", icon: "assistant" },
  { title: "Rückblick", icon: "dashboard" },
];

// ==================== SCROLL MATH ====================
// Smooth exponential acceleration: 10% faster every 0.2s (6 frames)

const V0 = 3.5;
const K = Math.log(1.1) / 6;

function scrollPos(f: number): number {
  if (f <= 0) return 0;
  return (V0 / K) * (Math.exp(K * f) - 1);
}

const BOX_W = 280;
const BOX_H = 110;
const BOX_GAP = 28;
const ROW_WIDTH = FEATURES.length * (BOX_W + BOX_GAP) - BOX_GAP;
const SCROLL_TARGET = ROW_WIDTH + 500;

let SCROLL_FRAMES = 200;
for (let f = 1; f < 500; f++) {
  if (scrollPos(f) >= SCROLL_TARGET) {
    SCROLL_FRAMES = f;
    break;
  }
}

// ==================== TIMELINE ====================
// All frame numbers relative to DashboardFlow start

const DASH_DUR = 100; // Dashboard visible with stats counting

// Zoom into "Funktionen"
const Z1_S = DASH_DUR;
const Z1_E = Z1_S + 25;

// Features scroll
const FEAT_S = Z1_E + 5;
const FEAT_SCROLL_E = FEAT_S + SCROLL_FRAMES;
const FEAT_MORE = FEAT_SCROLL_E + 20; // "Und vieles mehr" appears
const FEAT_HOLD_E = FEAT_MORE + 30;

// Zoom out from Funktionen
const ZO1_S = FEAT_HOLD_E;
const ZO1_E = ZO1_S + 20;

// Zoom into "Privat"
const Z2_S = ZO1_E + 8;
const Z2_E = Z2_S + 25;

// Privacy content
const PRIV_S = Z2_E;
const PRIV_E = PRIV_S + 110;

// Cross-fade to Offline
const OFF_S = PRIV_E;
const OFF_E = OFF_S + 110;

// Zoom out from Privat
const ZO2_S = OFF_E;
const ZO2_E = ZO2_S + 20;

// Zoom into "Plattformen" → deep zoom → black
const Z3_S = ZO2_E + 8;
const Z3_E = Z3_S + 35;

// CTA
const CTA_S = Z3_E;
const CTA_DUR = 240; // 8 seconds
const CTA_E = CTA_S + CTA_DUR;

export const FLOW_DURATION = CTA_E;

// Zoom targets (stat positions within 1920x1080 dashboard)
const STAT_CENTERS = [
  { x: 590, y: 850 }, // Funktionen
  { x: 960, y: 850 }, // Privat
  { x: 1330, y: 850 }, // Plattformen
];

// ==================== SUB-COMPONENTS ====================

const DashboardContent: React.FC<{ frame: number; fps: number }> = ({
  frame,
  fps,
}) => {
  const headO = interpolate(frame, [0, 20], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const headY = interpolate(frame, [0, 20], [20, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const imgO = interpolate(frame, [10, 30], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const statP = spring({
    frame: frame - 35,
    fps,
    config: { damping: 20, stiffness: 40, mass: 1.5 },
  });
  const statO = interpolate(frame - 35, [0, 15], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const stats = [
    { val: Math.round(12 * statP), suf: "+", label: "Funktionen" },
    { val: Math.round(100 * statP), suf: "%", label: "Privat" },
    { val: Math.round(5 * statP), suf: "", label: "Plattformen" },
  ];

  return (
    <div
      style={{
        position: "relative",
        width: 1920,
        height: 1080,
      }}
    >
      {/* Headline */}
      <div
        style={{
          position: "absolute",
          top: 80,
          left: 0,
          right: 0,
          textAlign: "center",
          opacity: headO,
          transform: `translateY(${headY}px)`,
          fontSize: 72,
          fontFamily: FONTS.display,
          fontWeight: 600,
          letterSpacing: -3,
          background: "linear-gradient(180deg, #ffffff 0%, #808085 100%)",
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
        }}
      >
        Alles an einem Ort.
      </div>

      {/* Screenshot */}
      <div
        style={{
          position: "absolute",
          top: 200,
          left: "17.5%",
          width: "65%",
          opacity: imgO,
          borderRadius: 12,
          overflow: "hidden",
          boxShadow: "0 30px 80px rgba(0,0,0,0.6)",
        }}
      >
        <Img
          src={staticFile("screenshots/dashboard.png")}
          style={{ width: "100%", display: "block" }}
        />
      </div>

      {/* Stats row */}
      {stats.map((s, i) => (
        <div
          key={i}
          style={{
            position: "absolute",
            top: 810,
            left: STAT_CENTERS[i].x - 100,
            width: 200,
            textAlign: "center",
            opacity: statO,
          }}
        >
          <div
            style={{
              fontSize: 64,
              fontFamily: FONTS.display,
              fontWeight: 600,
              letterSpacing: -2,
              background:
                "linear-gradient(180deg, #ffffff 0%, #808085 100%)",
              WebkitBackgroundClip: "text",
              WebkitTextFillColor: "transparent",
            }}
          >
            {s.val}
            {s.suf}
          </div>
          <div
            style={{
              fontSize: 16,
              fontFamily: FONTS.body,
              color: COLORS.gray,
              marginTop: 6,
              textTransform: "uppercase",
              letterSpacing: 3,
            }}
          >
            {s.label}
          </div>
        </div>
      ))}
    </div>
  );
};

// ---------- Features horizontal scroll ----------

const FeaturesContent: React.FC<{ localFrame: number }> = ({
  localFrame,
}) => {
  const scrollF = Math.max(0, localFrame);
  const sp = scrollPos(scrollF);

  // "Funktionen" headline
  const headO = interpolate(localFrame, [0, 15], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // "Und vieles mehr"
  const scrollDone = localFrame >= SCROLL_FRAMES;
  const moreLocalFrame = localFrame - SCROLL_FRAMES - 20;
  const moreO = interpolate(moreLocalFrame, [0, 12], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const moreScale = interpolate(moreLocalFrame, [0, 12], [0.88, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{ background: COLORS.black }}>
      {/* Headline */}
      <div
        style={{
          position: "absolute",
          top: 80,
          left: 0,
          right: 0,
          textAlign: "center",
          opacity: headO,
          fontSize: 18,
          fontFamily: FONTS.body,
          color: COLORS.gray,
          textTransform: "uppercase",
          letterSpacing: 4,
        }}
      >
        Funktionen
      </div>

      {/* Horizontal boxes */}
      <div
        style={{
          position: "absolute",
          top: 0,
          bottom: 0,
          left: 0,
          right: 0,
          overflow: "hidden",
          display: "flex",
          alignItems: "center",
        }}
      >
        {FEATURES.map((f, i) => {
          const x = 200 + i * (BOX_W + BOX_GAP) - sp;
          // Don't render if way off screen
          if (x < -BOX_W - 50 || x > 2000) return null;

          return (
            <div
              key={i}
              style={{
                position: "absolute",
                left: x,
                width: BOX_W,
                height: BOX_H,
                border: "1px solid rgba(255,255,255,0.1)",
                borderRadius: 18,
                background: "rgba(255,255,255,0.03)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                gap: 16,
              }}
            >
              <FeatureIcon
                name={f.icon}
                size={28}
                color={COLORS.lightGray}
                strokeWidth={1.5}
              />
              <span
                style={{
                  fontSize: 28,
                  fontFamily: FONTS.display,
                  fontWeight: 500,
                  letterSpacing: -0.5,
                  background:
                    "linear-gradient(180deg, #e0e0e5 0%, #808085 100%)",
                  WebkitBackgroundClip: "text",
                  WebkitTextFillColor: "transparent",
                }}
              >
                {f.title}
              </span>
            </div>
          );
        })}
      </div>

      {/* "Und vieles mehr." — appears after scroll */}
      {scrollDone && (
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            opacity: moreO,
            transform: `scale(${moreScale})`,
          }}
        >
          <div
            style={{
              fontSize: 56,
              fontFamily: FONTS.display,
              fontWeight: 600,
              letterSpacing: -1.5,
              background: GRADIENTS.brand,
              WebkitBackgroundClip: "text",
              WebkitTextFillColor: "transparent",
            }}
          >
            Und vieles mehr.
          </div>
        </div>
      )}
    </AbsoluteFill>
  );
};

// ---------- Privacy ----------

const PrivacyContent: React.FC<{ localFrame: number; fps: number }> = ({
  localFrame,
  fps,
}) => {
  const shieldP = spring({
    frame: localFrame - 5,
    fps,
    config: { damping: 20, stiffness: 40, mass: 1.5 },
  });

  const t1O = interpolate(localFrame, [5, 25], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const t1Y = interpolate(localFrame, [5, 25], [20, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const t2O = interpolate(localFrame, [15, 35], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const t2Y = interpolate(localFrame, [15, 35], [20, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const items = [
    "Ende-zu-Ende-Verschlüsselung",
    "Kein Tracking. Keine Analyse.",
    "Deine Daten bleiben bei dir.",
  ];

  return (
    <AbsoluteFill
      style={{ background: COLORS.black, display: "flex", alignItems: "center" }}
    >
      {/* Shield */}
      <div style={{ flex: 1, display: "flex", justifyContent: "center" }}>
        <svg width="180" height="220" viewBox="0 0 120 150" fill="none">
          <defs>
            <linearGradient id="sG" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor={COLORS.blue} />
              <stop offset="50%" stopColor={COLORS.purple} />
              <stop offset="100%" stopColor={COLORS.pink} />
            </linearGradient>
          </defs>
          <path
            d="M60 8 L112 38 L112 82 C112 116 90 135 60 146 C30 135 8 116 8 82 L8 38 Z"
            fill="none"
            stroke="url(#sG)"
            strokeWidth="1.5"
            strokeDasharray={400}
            strokeDashoffset={interpolate(shieldP, [0, 1], [400, 0])}
          />
          <path
            d="M42 78 L55 91 L82 58"
            stroke={COLORS.white}
            strokeWidth="3"
            strokeLinecap="round"
            strokeLinejoin="round"
            fill="none"
            strokeDasharray={80}
            strokeDashoffset={interpolate(shieldP, [0.5, 1], [80, 0], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            })}
          />
        </svg>
      </div>

      {/* Text */}
      <div style={{ flex: 1, paddingRight: 100 }}>
        <div
          style={{
            opacity: t1O,
            transform: `translateY(${t1Y}px)`,
            fontSize: 62,
            fontFamily: FONTS.display,
            fontWeight: 600,
            letterSpacing: -2,
            lineHeight: 1.12,
            background: "linear-gradient(180deg, #ffffff 0%, #808085 100%)",
            WebkitBackgroundClip: "text",
            WebkitTextFillColor: "transparent",
            marginBottom: 6,
          }}
        >
          Privatsphäre ist kein Feature.
        </div>
        <div
          style={{
            opacity: t2O,
            transform: `translateY(${t2Y}px)`,
            fontSize: 62,
            fontFamily: FONTS.display,
            fontWeight: 600,
            letterSpacing: -2,
            lineHeight: 1.12,
            background: GRADIENTS.brand,
            WebkitBackgroundClip: "text",
            WebkitTextFillColor: "transparent",
            marginBottom: 50,
          }}
        >
          Es ist das Fundament.
        </div>
        {items.map((text, i) => {
          const d = 30 + i * 10;
          return (
            <div
              key={i}
              style={{
                opacity: interpolate(localFrame - d, [0, 15], [0, 1], {
                  extrapolateLeft: "clamp",
                  extrapolateRight: "clamp",
                }),
                transform: `translateX(${interpolate(localFrame - d, [0, 15], [20, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })}px)`,
                display: "flex",
                alignItems: "center",
                gap: 14,
                marginBottom: 22,
              }}
            >
              <div
                style={{
                  width: 6,
                  height: 6,
                  borderRadius: "50%",
                  background: COLORS.gray,
                  flexShrink: 0,
                }}
              />
              <span
                style={{
                  fontSize: 24,
                  fontFamily: FONTS.body,
                  color: COLORS.lightGray,
                }}
              >
                {text}
              </span>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// ---------- Offline ----------

const OfflineContent: React.FC<{ localFrame: number; fps: number }> = ({
  localFrame,
  fps,
}) => {
  const iconP = spring({
    frame: localFrame - 5,
    fps,
    config: { damping: 20, stiffness: 40, mass: 1.5 },
  });

  const t1O = interpolate(localFrame, [5, 25], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const t1Y = interpolate(localFrame, [5, 25], [20, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const t2O = interpolate(localFrame, [15, 35], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const t2Y = interpolate(localFrame, [15, 35], [20, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const items = [
    "Alle Daten lokal gespeichert",
    "Kein Server nötig",
    "Sofort einsatzbereit",
  ];

  return (
    <AbsoluteFill
      style={{ background: COLORS.black, display: "flex", alignItems: "center" }}
    >
      {/* Wifi-off icon */}
      <div style={{ flex: 1, display: "flex", justifyContent: "center" }}>
        <svg width="180" height="180" viewBox="0 0 24 24" fill="none">
          <defs>
            <linearGradient id="wG" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor={COLORS.blue} />
              <stop offset="50%" stopColor={COLORS.purple} />
              <stop offset="100%" stopColor={COLORS.pink} />
            </linearGradient>
          </defs>
          <path
            d="M1 9l2 2c4.97-4.97 13.03-4.97 18 0l2-2C16.93 2.93 7.08 2.93 1 9z"
            stroke="url(#wG)"
            strokeWidth="1.2"
            fill="none"
            strokeDasharray={50}
            strokeDashoffset={interpolate(iconP, [0, 0.4], [50, 0], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            })}
          />
          <path
            d="M5 13l2 2c2.76-2.76 7.24-2.76 10 0l2-2C14.14 8.14 9.87 8.14 5 13z"
            stroke="url(#wG)"
            strokeWidth="1.2"
            fill="none"
            strokeDasharray={40}
            strokeDashoffset={interpolate(iconP, [0.2, 0.6], [40, 0], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            })}
          />
          <path
            d="M9 17l3 3 3-3c-1.65-1.66-4.34-1.66-6 0z"
            stroke="url(#wG)"
            strokeWidth="1.2"
            fill="none"
            strokeDasharray={20}
            strokeDashoffset={interpolate(iconP, [0.4, 0.8], [20, 0], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            })}
          />
          <path
            d="M2 2l20 20"
            stroke={COLORS.white}
            strokeWidth="1.5"
            strokeLinecap="round"
            fill="none"
            strokeDasharray={30}
            strokeDashoffset={interpolate(iconP, [0.6, 1], [30, 0], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            })}
          />
        </svg>
      </div>

      {/* Text */}
      <div style={{ flex: 1, paddingRight: 100 }}>
        <div
          style={{
            opacity: t1O,
            transform: `translateY(${t1Y}px)`,
            fontSize: 62,
            fontFamily: FONTS.display,
            fontWeight: 600,
            letterSpacing: -2,
            lineHeight: 1.12,
            background: "linear-gradient(180deg, #ffffff 0%, #808085 100%)",
            WebkitBackgroundClip: "text",
            WebkitTextFillColor: "transparent",
            marginBottom: 6,
          }}
        >
          Funktioniert ohne Internet.
        </div>
        <div
          style={{
            opacity: t2O,
            transform: `translateY(${t2Y}px)`,
            fontSize: 62,
            fontFamily: FONTS.display,
            fontWeight: 600,
            letterSpacing: -2,
            lineHeight: 1.12,
            background: GRADIENTS.brand,
            WebkitBackgroundClip: "text",
            WebkitTextFillColor: "transparent",
            marginBottom: 50,
          }}
        >
          Immer und überall.
        </div>
        {items.map((text, i) => {
          const d = 30 + i * 10;
          return (
            <div
              key={i}
              style={{
                opacity: interpolate(localFrame - d, [0, 15], [0, 1], {
                  extrapolateLeft: "clamp",
                  extrapolateRight: "clamp",
                }),
                transform: `translateX(${interpolate(localFrame - d, [0, 15], [20, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })}px)`,
                display: "flex",
                alignItems: "center",
                gap: 14,
                marginBottom: 22,
              }}
            >
              <div
                style={{
                  width: 6,
                  height: 6,
                  borderRadius: "50%",
                  background: COLORS.gray,
                  flexShrink: 0,
                }}
              />
              <span
                style={{
                  fontSize: 24,
                  fontFamily: FONTS.body,
                  color: COLORS.lightGray,
                }}
              >
                {text}
              </span>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

// ---------- CTA ----------

const CTAContent: React.FC<{ localFrame: number; totalFrames: number }> = ({
  localFrame,
  totalFrames,
}) => {
  // Fade out: last 90 frames fade, last 15 pure black
  const fadeStart = totalFrames - 90;
  const fadeEnd = totalFrames - 15;
  const masterO = interpolate(localFrame, [fadeStart, fadeEnd], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const logoO = interpolate(localFrame, [0, 25], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const logoS = interpolate(localFrame, [0, 25], [0.85, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const l1O = interpolate(localFrame, [10, 30], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const l1Y = interpolate(localFrame, [10, 30], [20, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const l2O = interpolate(localFrame, [20, 40], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const l2Y = interpolate(localFrame, [20, 40], [20, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const urlO = interpolate(localFrame, [55, 75], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const lineW = interpolate(localFrame, [70, 90], [0, 160], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const availO = interpolate(localFrame, [80, 95], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const platO = interpolate(localFrame, [95, 115], [0, 0.7], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        background: COLORS.black,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <div
        style={{
          opacity: masterO,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
        }}
      >
        <div
          style={{
            opacity: logoO,
            transform: `scale(${logoS})`,
            marginBottom: 50,
          }}
        >
          <Img
            src={staticFile("logo.png")}
            style={{ width: 110, height: 110 }}
          />
        </div>

        <div
          style={{
            opacity: l1O,
            transform: `translateY(${l1Y}px)`,
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
        <div
          style={{
            opacity: l2O,
            transform: `translateY(${l2Y}px)`,
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

        <div
          style={{
            opacity: urlO,
            marginTop: 60,
            fontSize: 26,
            fontFamily: FONTS.body,
            background: "linear-gradient(180deg, #ffffff 0%, #909095 100%)",
            WebkitBackgroundClip: "text",
            WebkitTextFillColor: "transparent",
            letterSpacing: 1.5,
          }}
        >
          {new URL(BRAND_WEBSITE).host}
        </div>
        <div
          style={{
            width: lineW,
            height: 1,
            background: GRADIENTS.brand,
            marginTop: 28,
            opacity: 0.4,
          }}
        />
        <div
          style={{
            opacity: availO,
            marginTop: 24,
            fontSize: 17,
            fontFamily: FONTS.body,
            color: COLORS.gray,
            letterSpacing: 4,
            textTransform: "uppercase",
          }}
        >
          Jetzt kostenlos verfügbar
        </div>
        <div
          style={{
            opacity: platO,
            marginTop: 30,
            display: "flex",
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
    </AbsoluteFill>
  );
};

// ==================== MAIN COMPONENT ====================

export const DashboardFlow: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // ---- Compute zoom state ----
  let zoomLevel = 1;
  let originX = 960;
  let originY = 540;
  let dashO = 1; // dashboard opacity

  // Helper for zoom phase
  const zoomPhase = (
    zIn: [number, number],
    zOut: [number, number],
    target: { x: number; y: number },
    maxZoom: number
  ) => {
    originX = target.x;
    originY = target.y;

    if (frame < zIn[1]) {
      // Zooming in
      const p = interpolate(frame, [zIn[0], zIn[1]], [0, 1], {
        extrapolateLeft: "clamp",
        extrapolateRight: "clamp",
      });
      zoomLevel = interpolate(p * p, [0, 1], [1, maxZoom]);
      dashO = interpolate(frame, [zIn[1] - 8, zIn[1]], [1, 0], {
        extrapolateLeft: "clamp",
        extrapolateRight: "clamp",
      });
    } else if (frame < zOut[0]) {
      // Fully zoomed — dashboard hidden
      zoomLevel = maxZoom;
      dashO = 0;
    } else {
      // Zooming out
      const p = interpolate(frame, [zOut[0], zOut[1]], [0, 1], {
        extrapolateLeft: "clamp",
        extrapolateRight: "clamp",
      });
      const eased = 1 - (1 - p) * (1 - p);
      zoomLevel = interpolate(eased, [0, 1], [maxZoom, 1]);
      dashO = interpolate(frame, [zOut[0], zOut[0] + 8], [0, 1], {
        extrapolateLeft: "clamp",
        extrapolateRight: "clamp",
      });
    }
  };

  // Apply zoom phases
  if (frame >= Z1_S && frame < ZO1_E) {
    zoomPhase([Z1_S, Z1_E], [ZO1_S, ZO1_E], STAT_CENTERS[0], 10);
  } else if (frame >= Z2_S && frame < ZO2_E) {
    zoomPhase([Z2_S, Z2_E], [ZO2_S, ZO2_E], STAT_CENTERS[1], 10);
  } else if (frame >= Z3_S) {
    // Deep zoom into Plattformen — no zoom out
    originX = STAT_CENTERS[2].x;
    originY = STAT_CENTERS[2].y;
    if (frame < Z3_E) {
      const p = interpolate(frame, [Z3_S, Z3_E], [0, 1], {
        extrapolateLeft: "clamp",
        extrapolateRight: "clamp",
      });
      zoomLevel = interpolate(p * p * p, [0, 1], [1, 60]);
      dashO = interpolate(frame, [Z3_E - 12, Z3_E], [1, 0], {
        extrapolateLeft: "clamp",
        extrapolateRight: "clamp",
      });
    } else {
      zoomLevel = 60;
      dashO = 0;
    }
  }

  // ---- Content layer opacities ----
  const featO = interpolate(
    frame,
    [Z1_E - 5, Z1_E + 5, ZO1_S - 5, ZO1_S + 5],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  // Privacy: fade in after Z2, fade out as offline starts
  const privO = interpolate(
    frame,
    [Z2_E - 5, Z2_E + 5, OFF_S - 10, OFF_S + 5],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  // Offline: fade in as privacy fades out, fade out before zoom out
  const offO = interpolate(
    frame,
    [OFF_S - 5, OFF_S + 10, ZO2_S - 5, ZO2_S + 5],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  // CTA
  const ctaO = interpolate(frame, [Z3_E - 5, Z3_E + 5], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{ background: COLORS.black }}>
      {/* Dashboard layer — with zoom transform */}
      <AbsoluteFill
        style={{
          transformOrigin: `${originX}px ${originY}px`,
          transform: `scale(${zoomLevel})`,
          opacity: dashO,
        }}
      >
        <DashboardContent frame={frame} fps={fps} />
      </AbsoluteFill>

      {/* Features layer */}
      {featO > 0.01 && (
        <AbsoluteFill style={{ opacity: featO }}>
          <FeaturesContent localFrame={frame - FEAT_S} />
        </AbsoluteFill>
      )}

      {/* Privacy layer */}
      {privO > 0.01 && (
        <AbsoluteFill style={{ opacity: privO }}>
          <PrivacyContent localFrame={frame - PRIV_S} fps={fps} />
        </AbsoluteFill>
      )}

      {/* Offline layer */}
      {offO > 0.01 && (
        <AbsoluteFill style={{ opacity: offO }}>
          <OfflineContent localFrame={frame - OFF_S} fps={fps} />
        </AbsoluteFill>
      )}

      {/* CTA layer */}
      {ctaO > 0.01 && (
        <AbsoluteFill style={{ opacity: ctaO }}>
          <CTAContent localFrame={frame - CTA_S} totalFrames={CTA_DUR} />
        </AbsoluteFill>
      )}
    </AbsoluteFill>
  );
};
