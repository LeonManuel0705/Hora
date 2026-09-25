import React from "react";
import {
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  AbsoluteFill,
} from "remotion";
import { COLORS, GRADIENTS, FONTS } from "./theme";
import { BRAND_NAME } from "./brand";

// ─── Deterministic random ─────────────────────────────────
function srand(seed: number): number {
  const x = Math.sin(seed * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
}

// ─── i18n ──────────────────────────────────────────────────
const i18n = {
  en: {
    hook1: "Your life runs on a dozen apps.",
    hook2: "What if you only needed one?",
    closer: `This is ${BRAND_NAME}.`,
    features: [
      {
        title: "School & Uni",
        bullets: ["Grade calculator", "A/B timetables", "Vertretungsplan"],
      },
      {
        title: "Public Transit",
        bullets: ["Offline routes", "Live delays", "Sparpreis alerts"],
      },
      {
        title: "Training",
        bullets: ["Log workouts", "Progress charts", "Rest detection"],
      },
      {
        title: "Life Management",
        bullets: ["Habit streaks", "Daily journal", "Finance tracker"],
      },
    ],
  },
  de: {
    hook1: "Dein Alltag läuft auf dutzend Apps.",
    hook2: "Was, wenn du nur eine bräuchtest?",
    closer: `Das ist ${BRAND_NAME}.`,
    features: [
      {
        title: "Schule & Uni",
        bullets: ["Notenrechner", "A/B-Stundenplan", "Vertretungsplan"],
      },
      {
        title: "Nahverkehr",
        bullets: ["Offline-Routen", "Live-Verspätungen", "Sparpreis-Alerts"],
      },
      {
        title: "Training",
        bullets: ["Workouts loggen", "Fortschritt-Charts", "Pausenerkennung"],
      },
      {
        title: "Lebensplanung",
        bullets: ["Gewohnheits-Streaks", "Tägliches Journal", "Finanz-Tracker"],
      },
    ],
  },
};

// ─── Particle data (40 particles) ─────────────────────────
const PARTICLE_COUNT = 40;
const particles = Array.from({ length: PARTICLE_COUNT }, (_, i) => ({
  angle: (i / PARTICLE_COUNT) * Math.PI * 2 + srand(i) * 0.6,
  speed: 0.4 + srand(i + 100) * 1.8,
  size: 3 + srand(i + 200) * 8,
  color:
    i % 3 === 0 ? COLORS.blue : i % 3 === 1 ? COLORS.purple : COLORS.pink,
  orbitRadius: 80 + srand(i + 300) * 320,
  delay: srand(i + 400) * 20,
  rotSpeed: 0.3 + srand(i + 500) * 0.8,
}));

// ─── Feature card meta ─────────────────────────────────────
const featureMeta = [
  {
    icon: "school",
    color: "#6366f1",
    from: [-500, 0] as [number, number],
  },
  {
    icon: "transit",
    color: "#ec4899",
    from: [500, 0] as [number, number],
  },
  {
    icon: "training",
    color: "#3b82f6",
    from: [0, 400] as [number, number],
  },
  {
    icon: "tasks",
    color: "#f97316",
    from: [0, -400] as [number, number],
  },
];

// ─── SVG icon paths ─────────────────────────────────────────
const iconPaths: Record<string, string> = {
  school:
    "M12 14l9-5-9-5-9 5 9 5zm0 0l6.16-3.422A12.083 12.083 0 0124 21H0a12.083 12.083 0 015.84-10.422L12 14zm0 0v7",
  transit:
    "M8 17l-2 4m10-4l2 4M6 2h12a2 2 0 012 2v10a2 2 0 01-2 2H6a2 2 0 01-2-2V4a2 2 0 012-2zm2 12h8M9 6h6",
  training: "M13 10V3L4 14h7v7l9-11h-7z",
  tasks:
    "M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4",
};

// ═════════════════════════════════════════════════════════════
// MAIN COMPONENT
// ═════════════════════════════════════════════════════════════

export const HeroVideo: React.FC<{ lang?: "en" | "de" }> = ({
  lang = "en",
}) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const cx = width / 2;
  const cy = height / 2;
  const t = i18n[lang];

  // ── Scene boundaries (15s = 900 frames at 60fps) ──
  const FEAT_START = 300;
  const FEAT_END = 720; // 5-12s

  // ── 1. Background glow ──
  const glowSize = interpolate(
    frame,
    [30, 150, 300, 720, 900],
    [0, 400, 300, 200, 600],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );
  const glowOpacity = interpolate(
    frame,
    [30, 90, 300, 800, 870, 900],
    [0, 0.5, 0.3, 0.3, 0.6, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  // ── 2. Particles ──
  const particleElements = particles.map((p, i) => {
    const born = 40 + p.delay;
    if (frame < born) return null;

    const localFrame = frame - born;

    const explodeProgress = interpolate(localFrame, [0, 60], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });

    const convergeProgress = interpolate(frame, [150, 280], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });

    const spreadProgress = interpolate(frame, [300, 400], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });

    const finaleProgress = interpolate(frame, [720, 820], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });

    const orbitAngle = p.angle + localFrame * 0.008 * p.rotSpeed;
    const explodeRadius = explodeProgress * p.orbitRadius;
    const orbitRadius =
      explodeRadius *
      (1 - convergeProgress * 0.6) *
      (1 + spreadProgress * 0.5);
    const finalRadius = orbitRadius * (1 - finaleProgress * 0.85);

    const x = cx + Math.cos(orbitAngle) * finalRadius;
    const y = cy + Math.sin(orbitAngle) * finalRadius;

    const alpha = interpolate(localFrame, [0, 15], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    const fadeOut = interpolate(frame, [860, 890], [1, 0], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });

    const pulse = 1 + Math.sin(localFrame * 0.05 + i) * 0.3;
    const sz = p.size * pulse;

    return (
      <div
        key={i}
        style={{
          position: "absolute",
          left: x - sz / 2,
          top: y - sz / 2,
          width: sz,
          height: sz,
          borderRadius: "50%",
          background: p.color,
          boxShadow: `0 0 ${sz * 2}px ${p.color}`,
          opacity: alpha * fadeOut * 0.7,
        }}
      />
    );
  });

  // ── 3. Hook text ──
  const hook1Opacity = interpolate(
    frame,
    [120, 160, 260, 290],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );
  const hook1Y = interpolate(frame, [120, 160], [25, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const hook2Opacity = interpolate(
    frame,
    [190, 230, 270, 300],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );
  const hook2Y = interpolate(frame, [190, 230], [20, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // ── Gradient line ──
  const lineWidth = interpolate(frame, [170, 230], [0, 400], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const lineOpacity = interpolate(
    frame,
    [170, 200, 270, 300],
    [0, 0.4, 0.4, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );
  const lineFinaleOpacity = interpolate(
    frame,
    [780, 810, 870, 900],
    [0, 0.35, 0.35, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );

  // ── Finale closer ──
  const closerOpacity = interpolate(
    frame,
    [760, 810, 870, 900],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
  );
  const closerY = interpolate(frame, [760, 810], [30, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const closerScale = interpolate(frame, [760, 810], [0.92, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // ── 4. Feature cards (liquid glass) ──
  const CARD_STAGGER = 80;

  const featureCards = featureMeta.map((feat, i) => {
    const cardStart = FEAT_START + i * CARD_STAGGER;
    const cardFrame = frame - cardStart;
    const ft = t.features[i];

    const entrance = spring({
      frame: Math.max(0, cardFrame),
      fps,
      config: { damping: 16, stiffness: 50, mass: 1 },
    });

    const exitFrame = frame - (FEAT_END - 30);
    const exit = interpolate(exitFrame, [0, 40], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });

    const opacity = entrance * (1 - exit);
    if (opacity < 0.01) return null;

    const fromX = feat.from[0];
    const fromY = feat.from[1];
    const x = fromX * (1 - entrance) + exit * fromX * 1.5;
    const y = fromY * (1 - entrance) + exit * fromY * 1.5;
    const scale = interpolate(entrance, [0, 1], [0.85, 1]);
    const rotateY = interpolate(
      entrance,
      [0, 1],
      [fromX > 0 ? 15 : -15, 0]
    );
    const rotateX = interpolate(
      entrance,
      [0, 1],
      [fromY > 0 ? -10 : 10, 0]
    );

    const col = i % 2;
    const row = Math.floor(i / 2);
    const gridX = -220 + col * 440;
    const gridY = -160 + row * 320;

    // Liquid glass: subtle animated specular highlight
    const specularX = 50 + Math.sin(frame * 0.015 + i * 1.5) * 30;
    const specularY = 30 + Math.cos(frame * 0.012 + i * 2) * 20;

    return (
      <div
        key={i}
        style={{
          position: "absolute",
          left: cx + gridX + x - 190,
          top: cy + gridY + y - 120,
          width: 380,
          padding: "32px 36px",
          borderRadius: 28,
          opacity,
          transform: `scale(${scale}) perspective(1000px) rotateY(${rotateY}deg) rotateX(${rotateX}deg)`,
          // Liquid glass: layered translucent fills with specular
          background: `
            radial-gradient(ellipse at ${specularX}% ${specularY}%, rgba(255,255,255,0.18) 0%, transparent 50%),
            radial-gradient(ellipse at ${100 - specularX}% ${100 - specularY}%, ${feat.color}15 0%, transparent 60%),
            linear-gradient(135deg, rgba(255,255,255,0.08) 0%, rgba(255,255,255,0.02) 50%, rgba(255,255,255,0.06) 100%)
          `,
          border: "1px solid rgba(255,255,255,0.15)",
          boxShadow: `
            0 8px 32px rgba(0,0,0,0.4),
            0 1px 0 rgba(255,255,255,0.1) inset,
            0 -1px 0 rgba(255,255,255,0.05) inset,
            0 0 0 0.5px rgba(255,255,255,0.08)
          `,
          backdropFilter: "blur(24px) saturate(1.4)",
          WebkitBackdropFilter: "blur(24px) saturate(1.4)",
        }}
      >
        {/* Icon — liquid glass pill */}
        <div
          style={{
            width: 48,
            height: 48,
            borderRadius: 16,
            background: `linear-gradient(135deg, ${feat.color}30 0%, ${feat.color}10 100%)`,
            border: `1px solid ${feat.color}40`,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            marginBottom: 16,
            boxShadow: `0 4px 12px ${feat.color}20`,
          }}
        >
          <svg
            width={24}
            height={24}
            viewBox="0 0 24 24"
            fill="none"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <path
              d={iconPaths[feat.icon]}
              stroke={feat.color}
              strokeWidth={1.8}
            />
          </svg>
        </div>
        {/* Title */}
        <div
          style={{
            fontSize: 28,
            fontFamily: FONTS.display,
            fontWeight: 700,
            color: COLORS.white,
            marginBottom: 14,
            letterSpacing: -0.5,
          }}
        >
          {ft.title}
        </div>
        {/* Bullets */}
        {ft.bullets.map((bullet, bi) => {
          const bulletOpacity = interpolate(
            cardFrame - 20 - bi * 8,
            [0, 12],
            [0, 1],
            { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
          );
          return (
            <div
              key={bi}
              style={{
                fontSize: 18,
                fontFamily: FONTS.body,
                color: "rgba(255,255,255,0.55)",
                marginBottom: 6,
                opacity: bulletOpacity * (1 - exit),
                display: "flex",
                alignItems: "center",
                gap: 8,
              }}
            >
              <div
                style={{
                  width: 5,
                  height: 5,
                  borderRadius: "50%",
                  background: feat.color,
                  opacity: 0.7,
                  flexShrink: 0,
                }}
              />
              {bullet}
            </div>
          );
        })}
      </div>
    );
  });

  // ── 5. Master fade to black ──
  const masterFade = interpolate(frame, [870, 900], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{ backgroundColor: COLORS.black }}>
      {/* Background glow */}
      <div
        style={{
          position: "absolute",
          left: cx - glowSize / 2,
          top: cy - glowSize / 2,
          width: glowSize,
          height: glowSize,
          borderRadius: "50%",
          background: `radial-gradient(circle, ${COLORS.purple}88 0%, ${COLORS.blue}44 40%, transparent 70%)`,
          opacity: glowOpacity,
          filter: "blur(40px)",
        }}
      />

      {/* Grain texture */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          opacity: 0.03,
          backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")`,
          backgroundSize: 256,
        }}
      />

      {/* Particles */}
      {particleElements}

      {/* Hook line 1 */}
      <div
        style={{
          position: "absolute",
          top: cy - 80,
          width: "100%",
          textAlign: "center",
          fontSize: 52,
          fontFamily: FONTS.display,
          fontWeight: 600,
          background: "linear-gradient(180deg, #e8e8ec 0%, #9a9aa0 100%)",
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
          opacity: hook1Opacity,
          transform: `translateY(${hook1Y}px)`,
          letterSpacing: -1,
        }}
      >
        {t.hook1}
      </div>

      {/* Gradient line */}
      <div
        style={{
          position: "absolute",
          left: cx - lineWidth / 2,
          top: cy + 5,
          width: lineWidth,
          height: 1,
          background: GRADIENTS.brand,
          opacity: Math.max(lineOpacity, lineFinaleOpacity),
        }}
      />

      {/* Hook line 2 */}
      <div
        style={{
          position: "absolute",
          top: cy + 30,
          width: "100%",
          textAlign: "center",
          fontSize: 52,
          fontFamily: FONTS.display,
          fontWeight: 600,
          background: "linear-gradient(180deg, #e8e8ec 0%, #9a9aa0 100%)",
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
          opacity: hook2Opacity,
          transform: `translateY(${hook2Y}px)`,
          letterSpacing: -1,
        }}
      >
        {t.hook2}
      </div>

      {/* Feature cards */}
      {featureCards}

      {/* Finale closer */}
      <div
        style={{
          position: "absolute",
          top: cy - 50,
          width: "100%",
          textAlign: "center",
          opacity: closerOpacity,
          transform: `translateY(${closerY}px) scale(${closerScale})`,
        }}
      >
        <div
          style={{
            fontSize: 80,
            fontFamily: FONTS.display,
            fontWeight: 700,
            background: GRADIENTS.brand,
            WebkitBackgroundClip: "text",
            WebkitTextFillColor: "transparent",
            letterSpacing: -3,
          }}
        >
          {t.closer}
        </div>
      </div>

      {/* Master fade to black */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          background: COLORS.black,
          opacity: masterFade,
        }}
      />
    </AbsoluteFill>
  );
};
