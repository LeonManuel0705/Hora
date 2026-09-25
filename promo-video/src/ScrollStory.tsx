import React from "react";
import {
  useCurrentFrame,
  interpolate,
  staticFile,
  Img,
  AbsoluteFill,
  Easing,
} from "remotion";
import { COLORS, GRADIENTS, FONTS } from "./theme";
import { BRAND_NAME } from "./brand";

/**
 * ScrollStory — Cinematic scroll-driven sequence
 *
 * 1000 frames at 30fps ≈ 33 seconds
 *
 * Scene 1 — Genesis (0–120): Logo appears in particle field
 * Scene 2 — Assembly (120–300): Particles converge into geometric form
 * Scene 3 — Product Reveal (300–450): Object rotates cinematically
 * Scene 4 — Interface Explosion (450–650): Panels fly out showing features
 * Scene 5 — Network Expansion (650–850): Nodes & connections grow
 * Scene 6 — Final State (850–1000): Collapse to clean CTA, fade to white
 */

// ── Deterministic pseudo-random (seeded) ──
function seededRandom(seed: number): number {
  const x = Math.sin(seed * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
}

// ── Generate particle positions ──
const PARTICLE_COUNT = 80;
const particles = Array.from({ length: PARTICLE_COUNT }, (_, i) => ({
  x: seededRandom(i * 2) * 1920,
  y: seededRandom(i * 2 + 1) * 1080,
  size: 1 + seededRandom(i * 3) * 3,
  speed: 0.3 + seededRandom(i * 4) * 0.7,
  phase: seededRandom(i * 5) * Math.PI * 2,
}));

// ── Geometric shape vertices (hexagonal crystal) ──
const HEX_POINTS = 6;
const hexVertices = Array.from({ length: HEX_POINTS }, (_, i) => {
  const angle = (i / HEX_POINTS) * Math.PI * 2 - Math.PI / 2;
  return { x: Math.cos(angle) * 120, y: Math.sin(angle) * 120 };
});

// Inner ring
const innerVertices = Array.from({ length: HEX_POINTS }, (_, i) => {
  const angle = (i / HEX_POINTS) * Math.PI * 2 - Math.PI / 2 + Math.PI / 6;
  return { x: Math.cos(angle) * 60, y: Math.sin(angle) * 60 };
});

// ── UI Panel data ──
const uiPanels = [
  { icon: "📅", label: "Calendar", angle: 0, dist: 300 },
  { icon: "📧", label: "Email", angle: 60, dist: 280 },
  { icon: "✅", label: "Tasks", angle: 120, dist: 320 },
  { icon: "🎓", label: "School", angle: 180, dist: 290 },
  { icon: "🚇", label: "Transit", angle: 240, dist: 310 },
  { icon: "📝", label: "Notes", angle: 300, dist: 270 },
];

// ── Network nodes ──
const networkNodes = Array.from({ length: 20 }, (_, i) => ({
  x: seededRandom(i * 10 + 100) * 1400 + 260,
  y: seededRandom(i * 10 + 101) * 800 + 140,
  size: 4 + seededRandom(i * 10 + 102) * 8,
  delay: i * 8,
}));

// ── Network connections ──
const networkEdges: Array<[number, number]> = [];
for (let i = 0; i < networkNodes.length; i++) {
  for (let j = i + 1; j < networkNodes.length; j++) {
    const dx = networkNodes[i].x - networkNodes[j].x;
    const dy = networkNodes[i].y - networkNodes[j].y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist < 350) {
      networkEdges.push([i, j]);
    }
  }
}

export const ScrollStory: React.FC = () => {
  const frame = useCurrentFrame();

  // ════════════════════════════════════════
  // SCENE 1: GENESIS (0–120)
  // ════════════════════════════════════════
  const s1Opacity = interpolate(frame, [0, 10, 100, 120], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const logoOpacity = interpolate(frame, [20, 60], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const logoScale = interpolate(frame, [0, 120], [0.8, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const genesisTextOpacity = interpolate(frame, [50, 75], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const genesisTextY = interpolate(frame, [50, 75], [20, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // ════════════════════════════════════════
  // SCENE 2: ASSEMBLY (120–300)
  // ════════════════════════════════════════
  const s2Opacity = interpolate(frame, [110, 130, 280, 300], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // How far particles have converged (0 = scattered, 1 = assembled)
  const assemblyProgress = interpolate(frame, [130, 270], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.inOut(Easing.cubic),
  });

  // Glow intensity at center
  const assemblyGlow = interpolate(frame, [200, 280], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // ════════════════════════════════════════
  // SCENE 3: PRODUCT REVEAL (300–450)
  // ════════════════════════════════════════
  const s3Opacity = interpolate(frame, [290, 310, 430, 450], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const revealRotation = interpolate(frame, [300, 450], [0, 120], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const revealScale = interpolate(frame, [300, 370], [0.8, 1.1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // Light sweep across object
  const lightSweep = interpolate(frame, [320, 420], [-200, 200], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // ════════════════════════════════════════
  // SCENE 4: INTERFACE EXPLOSION (450–650)
  // ════════════════════════════════════════
  const s4Opacity = interpolate(frame, [440, 460, 630, 650], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const explosionProgress = interpolate(frame, [460, 530], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const s4TextOpacity = interpolate(frame, [530, 560], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const s4Text2Opacity = interpolate(frame, [560, 590], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // ════════════════════════════════════════
  // SCENE 5: NETWORK EXPANSION (650–850)
  // ════════════════════════════════════════
  const s5Opacity = interpolate(frame, [640, 660, 830, 850], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const networkProgress = interpolate(frame, [660, 800], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // ════════════════════════════════════════
  // SCENE 6: FINAL STATE (850–1000)
  // ════════════════════════════════════════
  const s6Opacity = interpolate(frame, [840, 870, 980, 1000], [0, 1, 1, 0.8], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const bgWhiteOpacity = interpolate(frame, [860, 960], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const finalLogoScale = interpolate(frame, [870, 920], [0.5, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const finalTextOpacity = interpolate(frame, [900, 930], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const finalTextY = interpolate(frame, [900, 930], [30, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // ── Global ambient ──
  const ambientPulse = Math.sin(frame * 0.02) * 0.15 + 0.85;

  return (
    <AbsoluteFill
      style={{
        backgroundColor: COLORS.black,
        fontFamily: FONTS.display,
        overflow: "hidden",
      }}
    >
      {/* White background for scene 6 transition */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          backgroundColor: "#ffffff",
          opacity: bgWhiteOpacity,
          zIndex: 0,
        }}
      />

      {/* ═══════════════════════════════════════════
          SCENE 1: GENESIS — Logo in particle field
          ═══════════════════════════════════════════ */}
      <AbsoluteFill style={{ opacity: s1Opacity, zIndex: 10 }}>
        {/* Particles */}
        <svg
          width="1920"
          height="1080"
          style={{ position: "absolute", inset: 0 }}
        >
          {particles.map((p, i) => {
            const drift = Math.sin(frame * 0.01 * p.speed + p.phase) * 20;
            const driftY = Math.cos(frame * 0.008 * p.speed + p.phase) * 15;
            const pOpacity = interpolate(frame, [i * 0.3, i * 0.3 + 20], [0, 0.4 + seededRandom(i * 7) * 0.4], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            });
            return (
              <circle
                key={i}
                cx={p.x + drift}
                cy={p.y + driftY}
                r={p.size}
                fill={i % 3 === 0 ? COLORS.blue : i % 3 === 1 ? COLORS.purple : COLORS.pink}
                opacity={pOpacity * ambientPulse}
              />
            );
          })}
        </svg>

        {/* Center glow */}
        <div
          style={{
            position: "absolute",
            left: "50%",
            top: "50%",
            transform: "translate(-50%, -50%)",
            width: 400,
            height: 400,
            borderRadius: "50%",
            background: `radial-gradient(circle, ${COLORS.purple}22 0%, transparent 70%)`,
            filter: "blur(60px)",
            opacity: logoOpacity,
          }}
        />

        {/* Logo */}
        <div
          style={{
            position: "absolute",
            left: "50%",
            top: "42%",
            transform: `translate(-50%, -50%) scale(${logoScale})`,
            opacity: logoOpacity,
          }}
        >
          <Img
            src={staticFile("logo.png")}
            style={{ width: 140, height: 140 }}
          />
        </div>

        {/* Genesis text */}
        <div
          style={{
            position: "absolute",
            left: "50%",
            top: "60%",
            transform: `translate(-50%, -50%) translateY(${genesisTextY}px)`,
            opacity: genesisTextOpacity,
            fontSize: 28,
            fontFamily: FONTS.body,
            fontWeight: 400,
            color: COLORS.lightGray,
            letterSpacing: 1,
            textAlign: "center",
          }}
        >
          Everything starts with a connection.
        </div>
      </AbsoluteFill>

      {/* ═══════════════════════════════════════════
          SCENE 2: ASSEMBLY — Particles converge
          ═══════════════════════════════════════════ */}
      <AbsoluteFill style={{ opacity: s2Opacity, zIndex: 10 }}>
        <svg
          width="1920"
          height="1080"
          style={{ position: "absolute", inset: 0 }}
        >
          <defs>
            <linearGradient id="crystalGrad" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor={COLORS.blue} />
              <stop offset="50%" stopColor={COLORS.purple} />
              <stop offset="100%" stopColor={COLORS.pink} />
            </linearGradient>
            <filter id="glow">
              <feGaussianBlur stdDeviation="4" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>

          {/* Particles converging to center */}
          {particles.map((p, i) => {
            // Target position: map to hex/inner vertices
            const targetIdx = i % (hexVertices.length + innerVertices.length);
            const isInner = targetIdx >= hexVertices.length;
            const verts = isInner ? innerVertices : hexVertices;
            const vertIdx = isInner
              ? targetIdx - hexVertices.length
              : targetIdx;
            const target = verts[vertIdx % verts.length];

            const cx = 960; // center x
            const cy = 540; // center y

            const currentX =
              p.x + (cx + target.x - p.x) * assemblyProgress;
            const currentY =
              p.y + (cy + target.y - p.y) * assemblyProgress;

            const pSize = interpolate(
              assemblyProgress,
              [0, 0.8, 1],
              [p.size, p.size * 1.5, 2],
              { extrapolateRight: "clamp" }
            );

            return (
              <circle
                key={i}
                cx={currentX}
                cy={currentY}
                r={pSize}
                fill={
                  i % 3 === 0
                    ? COLORS.blue
                    : i % 3 === 1
                    ? COLORS.purple
                    : COLORS.pink
                }
                opacity={0.6 + assemblyProgress * 0.4}
              />
            );
          })}

          {/* Forming hexagonal shape (appears as particles converge) */}
          {assemblyProgress > 0.5 && (
            <g
              transform="translate(960, 540)"
              opacity={(assemblyProgress - 0.5) * 2}
              filter="url(#glow)"
            >
              {/* Outer hexagon */}
              <polygon
                points={hexVertices
                  .map((v) => `${v.x},${v.y}`)
                  .join(" ")}
                fill="none"
                stroke="url(#crystalGrad)"
                strokeWidth="1.5"
              />
              {/* Inner hexagon */}
              <polygon
                points={innerVertices
                  .map((v) => `${v.x},${v.y}`)
                  .join(" ")}
                fill="none"
                stroke="url(#crystalGrad)"
                strokeWidth="1"
                opacity="0.6"
              />
              {/* Connections between inner and outer */}
              {hexVertices.map((v, i) => (
                <line
                  key={`conn-${i}`}
                  x1={v.x}
                  y1={v.y}
                  x2={innerVertices[i].x}
                  y2={innerVertices[i].y}
                  stroke="url(#crystalGrad)"
                  strokeWidth="0.8"
                  opacity="0.4"
                />
              ))}
              {/* Center dot */}
              <circle
                cx="0"
                cy="0"
                r="4"
                fill={COLORS.purple}
                opacity={assemblyProgress}
              />
            </g>
          )}
        </svg>

        {/* Center glow intensifying */}
        <div
          style={{
            position: "absolute",
            left: "50%",
            top: "50%",
            transform: "translate(-50%, -50%)",
            width: 500,
            height: 500,
            borderRadius: "50%",
            background: `radial-gradient(circle, ${COLORS.purple}${Math.round(assemblyGlow * 40).toString(16).padStart(2, "0")} 0%, transparent 70%)`,
            filter: "blur(50px)",
          }}
        />
      </AbsoluteFill>

      {/* ═══════════════════════════════════════════
          SCENE 3: PRODUCT REVEAL — Rotating crystal
          ═══════════════════════════════════════════ */}
      <AbsoluteFill style={{ opacity: s3Opacity, zIndex: 10 }}>
        {/* Background glow */}
        <div
          style={{
            position: "absolute",
            left: "50%",
            top: "50%",
            transform: "translate(-50%, -50%)",
            width: 600,
            height: 600,
            borderRadius: "50%",
            background: `radial-gradient(circle, ${COLORS.blue}30 0%, ${COLORS.purple}15 40%, transparent 70%)`,
            filter: "blur(40px)",
          }}
        />

        {/* Rotating geometric crystal */}
        <svg
          width="1920"
          height="1080"
          style={{ position: "absolute", inset: 0 }}
        >
          <defs>
            <linearGradient id="revealGrad" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor={COLORS.blue} stopOpacity="0.9" />
              <stop offset="50%" stopColor={COLORS.purple} stopOpacity="0.9" />
              <stop offset="100%" stopColor={COLORS.pink} stopOpacity="0.9" />
            </linearGradient>
            <filter id="glow2">
              <feGaussianBlur stdDeviation="6" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>

          <g
            transform={`translate(960, 540) rotate(${revealRotation}) scale(${revealScale})`}
            filter="url(#glow2)"
          >
            {/* Multi-layered crystal */}
            {/* Outer ring */}
            <polygon
              points={Array.from({ length: 8 }, (_, i) => {
                const a = (i / 8) * Math.PI * 2 - Math.PI / 2;
                return `${Math.cos(a) * 160},${Math.sin(a) * 160}`;
              }).join(" ")}
              fill="none"
              stroke="url(#revealGrad)"
              strokeWidth="2"
            />

            {/* Middle hexagon */}
            <polygon
              points={hexVertices
                .map((v) => `${v.x * 1.2},${v.y * 1.2}`)
                .join(" ")}
              fill="none"
              stroke="url(#revealGrad)"
              strokeWidth="1.5"
              opacity="0.8"
            />

            {/* Inner structure */}
            <polygon
              points={innerVertices
                .map((v) => `${v.x * 1.2},${v.y * 1.2}`)
                .join(" ")}
              fill={`${COLORS.purple}08`}
              stroke="url(#revealGrad)"
              strokeWidth="1"
              opacity="0.6"
            />

            {/* Radial lines */}
            {Array.from({ length: 12 }, (_, i) => {
              const a = (i / 12) * Math.PI * 2;
              return (
                <line
                  key={`rad-${i}`}
                  x1={Math.cos(a) * 30}
                  y1={Math.sin(a) * 30}
                  x2={Math.cos(a) * 160}
                  y2={Math.sin(a) * 160}
                  stroke="url(#revealGrad)"
                  strokeWidth="0.5"
                  opacity="0.3"
                />
              );
            })}

            {/* Center point */}
            <circle cx="0" cy="0" r="8" fill="url(#revealGrad)" opacity="0.9" />
            <circle cx="0" cy="0" r="20" fill="none" stroke="url(#revealGrad)" strokeWidth="1" opacity="0.4" />
          </g>

          {/* Light sweep */}
          <rect
            x={960 + lightSweep - 30}
            y={340}
            width="60"
            height="400"
            fill="url(#revealGrad)"
            opacity="0.08"
            style={{ filter: "blur(30px)" }}
          />
        </svg>
      </AbsoluteFill>

      {/* ═══════════════════════════════════════════
          SCENE 4: INTERFACE EXPLOSION — Panels fly out
          ═══════════════════════════════════════════ */}
      <AbsoluteFill style={{ opacity: s4Opacity, zIndex: 10 }}>
        {/* Central burst */}
        <div
          style={{
            position: "absolute",
            left: "50%",
            top: "50%",
            transform: "translate(-50%, -50%)",
            width: 200,
            height: 200,
            borderRadius: "50%",
            background: `radial-gradient(circle, ${COLORS.purple}40 0%, transparent 70%)`,
            filter: "blur(30px)",
            opacity: 1 - explosionProgress,
          }}
        />

        {/* Flying UI panels */}
        {uiPanels.map((panel, i) => {
          const angleRad = (panel.angle * Math.PI) / 180;
          const currentDist = explosionProgress * panel.dist;
          const panelX = Math.cos(angleRad) * currentDist;
          const panelY = Math.sin(angleRad) * currentDist * 0.7;

          const panelOpacity = interpolate(
            frame,
            [465 + i * 6, 480 + i * 6],
            [0, 1],
            { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
          );

          const panelRotation = interpolate(
            explosionProgress,
            [0, 1],
            [0, (seededRandom(i * 20) - 0.5) * 15],
            { extrapolateRight: "clamp" }
          );

          return (
            <div
              key={panel.label}
              style={{
                position: "absolute",
                left: `calc(50% + ${panelX}px)`,
                top: `calc(50% + ${panelY}px)`,
                transform: `translate(-50%, -50%) rotate(${panelRotation}deg)`,
                opacity: panelOpacity,
                display: "flex",
                alignItems: "center",
                gap: 14,
                padding: "20px 32px",
                borderRadius: 20,
                background: "rgba(255,255,255,0.06)",
                backdropFilter: "blur(20px)",
                border: "1px solid rgba(255,255,255,0.12)",
                boxShadow: `0 8px 40px rgba(0,0,0,0.3), inset 0 1px 0 rgba(255,255,255,0.1)`,
              }}
            >
              <span style={{ fontSize: 36 }}>{panel.icon}</span>
              <span
                style={{
                  fontSize: 22,
                  color: COLORS.white,
                  fontFamily: FONTS.body,
                  fontWeight: 500,
                }}
              >
                {panel.label}
              </span>
            </div>
          );
        })}

        {/* Text: "Not an app." */}
        <div
          style={{
            position: "absolute",
            left: "50%",
            top: "50%",
            transform: "translate(-50%, -50%)",
            textAlign: "center",
            opacity: s4TextOpacity,
          }}
        >
          <div
            style={{
              fontSize: 56,
              fontWeight: 700,
              color: COLORS.white,
              lineHeight: 1.2,
              marginBottom: 10,
            }}
          >
            Not an app.
          </div>
          <div
            style={{
              fontSize: 56,
              fontWeight: 700,
              background: GRADIENTS.brand,
              WebkitBackgroundClip: "text",
              WebkitTextFillColor: "transparent",
              opacity: s4Text2Opacity,
            }}
          >
            A system.
          </div>
        </div>

        {/* Connecting lines from center to panels */}
        <svg
          width="1920"
          height="1080"
          style={{ position: "absolute", inset: 0, opacity: explosionProgress * 0.15 }}
        >
          {uiPanels.map((panel, i) => {
            const angleRad = (panel.angle * Math.PI) / 180;
            const dx = Math.cos(angleRad) * explosionProgress * panel.dist;
            const dy = Math.sin(angleRad) * explosionProgress * panel.dist * 0.7;
            return (
              <line
                key={i}
                x1={960}
                y1={540}
                x2={960 + dx}
                y2={540 + dy}
                stroke="url(#crystalGrad)"
                strokeWidth="1"
                strokeDasharray="4 4"
              />
            );
          })}
          <defs>
            <linearGradient id="crystalGrad2" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor={COLORS.blue} />
              <stop offset="100%" stopColor={COLORS.pink} />
            </linearGradient>
          </defs>
        </svg>
      </AbsoluteFill>

      {/* ═══════════════════════════════════════════
          SCENE 5: NETWORK EXPANSION
          ═══════════════════════════════════════════ */}
      <AbsoluteFill style={{ opacity: s5Opacity, zIndex: 10 }}>
        <svg
          width="1920"
          height="1080"
          style={{ position: "absolute", inset: 0 }}
        >
          <defs>
            <linearGradient id="netGrad" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor={COLORS.blue} />
              <stop offset="50%" stopColor={COLORS.purple} />
              <stop offset="100%" stopColor={COLORS.pink} />
            </linearGradient>
            <filter id="nodeGlow">
              <feGaussianBlur stdDeviation="3" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>

          {/* Connections */}
          {networkEdges.map(([a, b], i) => {
            const nodeA = networkNodes[a];
            const nodeB = networkNodes[b];
            const edgeDelay = Math.max(nodeA.delay, nodeB.delay);
            const edgeProgress = interpolate(
              frame,
              [660 + edgeDelay, 680 + edgeDelay],
              [0, 1],
              { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
            );
            return (
              <line
                key={`edge-${i}`}
                x1={nodeA.x}
                y1={nodeA.y}
                x2={nodeA.x + (nodeB.x - nodeA.x) * edgeProgress}
                y2={nodeA.y + (nodeB.y - nodeA.y) * edgeProgress}
                stroke="url(#netGrad)"
                strokeWidth="1"
                opacity={edgeProgress * 0.3}
              />
            );
          })}

          {/* Nodes */}
          {networkNodes.map((node, i) => {
            const nodeOpacity = interpolate(
              frame,
              [660 + node.delay, 670 + node.delay],
              [0, 1],
              { extrapolateLeft: "clamp", extrapolateRight: "clamp" }
            );
            const nodeScale = interpolate(
              frame,
              [660 + node.delay, 675 + node.delay],
              [0, 1],
              {
                extrapolateLeft: "clamp",
                extrapolateRight: "clamp",
                easing: Easing.out(Easing.back(2)),
              }
            );
            const pulse = Math.sin(frame * 0.03 + i) * 0.15 + 1;
            return (
              <g key={`node-${i}`} opacity={nodeOpacity} filter="url(#nodeGlow)">
                {/* Outer ring */}
                <circle
                  cx={node.x}
                  cy={node.y}
                  r={node.size * nodeScale * pulse * 1.8}
                  fill="none"
                  stroke={i % 3 === 0 ? COLORS.blue : i % 3 === 1 ? COLORS.purple : COLORS.pink}
                  strokeWidth="0.5"
                  opacity="0.3"
                />
                {/* Core */}
                <circle
                  cx={node.x}
                  cy={node.y}
                  r={node.size * nodeScale}
                  fill={
                    i % 3 === 0
                      ? COLORS.blue
                      : i % 3 === 1
                      ? COLORS.purple
                      : COLORS.pink
                  }
                  opacity="0.8"
                />
              </g>
            );
          })}
        </svg>

        {/* Central label */}
        <div
          style={{
            position: "absolute",
            left: "50%",
            bottom: 120,
            transform: "translateX(-50%)",
            textAlign: "center",
            opacity: networkProgress,
          }}
        >
          <div
            style={{
              fontSize: 24,
              fontFamily: FONTS.body,
              color: COLORS.lightGray,
              letterSpacing: 2,
              textTransform: "uppercase",
            }}
          >
            Connected by design
          </div>
        </div>
      </AbsoluteFill>

      {/* ═══════════════════════════════════════════
          SCENE 6: FINAL STATE — Clean CTA
          ═══════════════════════════════════════════ */}
      <AbsoluteFill
        style={{
          opacity: s6Opacity,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          zIndex: 10,
        }}
      >
        {/* Logo */}
        <div
          style={{
            opacity: finalLogoScale > 0.5 ? 1 : 0,
            transform: `scale(${finalLogoScale})`,
            marginBottom: 40,
          }}
        >
          <Img
            src={staticFile("logo.png")}
            style={{ width: 80, height: 80 }}
          />
        </div>

        {/* Welcome text */}
        <div
          style={{
            opacity: finalTextOpacity,
            transform: `translateY(${finalTextY}px)`,
            textAlign: "center",
          }}
        >
          <div
            style={{
              fontSize: 64,
              fontWeight: 700,
              color: bgWhiteOpacity > 0.5 ? COLORS.darkGray : COLORS.white,
              lineHeight: 1.2,
              marginBottom: 10,
            }}
          >
            Welcome to
          </div>
          <div
            style={{
              fontSize: 80,
              fontWeight: 700,
              background: GRADIENTS.brand,
              WebkitBackgroundClip: "text",
              WebkitTextFillColor: "transparent",
              letterSpacing: -2,
            }}
          >
            {BRAND_NAME}
          </div>
        </div>
      </AbsoluteFill>

      {/* Grain overlay */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          opacity: 0.03,
          mixBlendMode: "overlay",
          backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")`,
          zIndex: 50,
          pointerEvents: "none",
        }}
      />
    </AbsoluteFill>
  );
};
