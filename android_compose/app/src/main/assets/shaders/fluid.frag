#include <flutter/runtime_effect.glsl>

// ─────────────────────────────────────────────────────────────────────────────
// fluid.frag  —  Dynamic Color-Shifting Mesh Gradient
//
// Every time-dependent value is precomputed once per animation tick on the CPU
// (Dart, float64) and passed in as uniforms: mesh node positions, node colours
// (palette rotation), the ambient-shadow phase and the film-grain phase.
//
// Why: the old version recomputed sin()/cos()/smoothstep()/mix() for every one
// of the 131,072 fragments even though the inputs were identical for all of
// them, and it fed an unbounded uTime to the GPU where float32 sin()/fract()
// precision degrades after long uptimes. With precomputed uniforms neither
// problem exists — no time wrap discontinuity is possible and precision stays
// exact. Keep time-only math out of this file; add new uniforms instead.
// ─────────────────────────────────────────────────────────────────────────────

uniform vec2  uSize;
uniform vec2  uNode0;       // mesh node positions, precomputed per tick
uniform vec2  uNode1;
uniform vec2  uNode2;
uniform vec2  uNode3;
uniform vec3  uNodeColor0;  // rotated palette colours, precomputed per tick
uniform vec3  uNodeColor1;
uniform vec3  uNodeColor2;
uniform vec3  uNodeColor3;
uniform vec3  uShadow;      // dark depth — also the ambient shadow tint
uniform float uShadowPhase; // (uTime * 0.2) mod 2π — keeps sin() bounded
uniform float uGrainPhase;  // uTime mod 1.0     — keeps fract() bounded

out vec4 fragColor;

// Squared-distance falloff — no sqrt. 0.59 ≈ radius 1.3 in the old setup.
float getWeight(vec2 uv, vec2 p) {
  float d = max(0.0, 1.0 - dot(uv - p, uv - p) * 0.59);
  return d * d;
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;

  // ── 1. Mesh Grid Weighting ────────────────────────────────────────────────
  float w0 = getWeight(uv, uNode0);
  float w1 = getWeight(uv, uNode1);
  float w2 = getWeight(uv, uNode2);
  float w3 = getWeight(uv, uNode3);

  // ── 2. Normalized Node Colour Blend ───────────────────────────────────────
  float totalW = w0 + w1 + w2 + w3 + 0.001;
  vec3 col = (uNodeColor0 * w0 + uNodeColor1 * w1 + uNodeColor2 * w2 + uNodeColor3 * w3) / totalW;

  // ── 3. Subtle Ambient Shadow Blend ────────────────────────────────────────
  float shadowMask = smoothstep(0.2, 0.9, uv.y + 0.2 * sin(uv.x * 3.0 + uShadowPhase));
  col = mix(col, uShadow, shadowMask * 0.12);

  // ── 4. Dithering Film Grain ───────────────────────────────────────────────
  vec2 grainUV = fragCoord + uGrainPhase * 82.2;
  float grain = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.02);

  // ── 5. Soft Vignette ──────────────────────────────────────────────────────
  vec2 vC = uv - 0.5;
  float vig = clamp(1.0 - dot(vC, vC) * 0.3, 0.0, 1.0);
  col *= vig;

  fragColor = vec4(col, 1.0);
}
