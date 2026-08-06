#include <flutter/runtime_effect.glsl>

// ─────────────────────────────────────────────────────────────────────────────
// fluid.frag  —  Dynamic Color-Shifting Mesh Gradient (Optimized & Sleek)
// ─────────────────────────────────────────────────────────────────────────────

uniform vec2  uSize;
uniform float uTime;
uniform vec3  uColor0;    // Dominant
uniform vec3  uColor1;    // Supporting
uniform vec3  uColor2;    // Accent
uniform vec3  uHighlight; // Bright pop
uniform vec3  uShadow;    // Dark depth

out vec4 fragColor;

// fract() is the new mod(). Lebih enteng tapi result sama.
vec3 shiftPalette(float progress, vec3 colA, vec3 colB, vec3 colC) {
  float p = fract(progress * 0.333333) * 3.0; 
  if (p < 1.0) return mix(colA, colB, smoothstep(0.0, 1.0, p));
  if (p < 2.0) return mix(colB, colC, smoothstep(0.0, 1.0, p - 1.0));
  return mix(colC, colA, smoothstep(0.0, 1.0, p - 2.0));
}

// Helper buat bypass length() & smoothstep(). No sqrt = GPU lu bisa nafas lega
float getWeight(vec2 uv, vec2 p) {
  // Angka 0.59 ini kurang lebih setara radius 1.3 di setup lama lu.
  float d = max(0.0, 1.0 - dot(uv - p, uv - p) * 0.59);
  return d * d; // Dikuadratin biar dapet falloff curve ala smoothstep
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;
  float t = uTime;

  // ── 1. Mesh Grid Node Distortions ────────────────────────────────────────
  vec2 p00 = vec2(0.0, 0.0) + vec2(0.20 * sin(t * 0.11), 0.20 * cos(t * 0.13));
  vec2 p10 = vec2(1.0, 0.0) + vec2(0.20 * cos(t * 0.09), 0.20 * sin(t * 0.15));
  vec2 p01 = vec2(0.0, 1.0) + vec2(0.20 * sin(t * 0.14), 0.20 * cos(t * 0.10));
  vec2 p11 = vec2(1.0, 1.0) + vec2(0.20 * cos(t * 0.12), 0.20 * sin(t * 0.08));

  // ── 2. Landai Weighting (Lightweight AF) ─────────────────────────────────
  float w00 = getWeight(uv, p00);
  float w10 = getWeight(uv, p10);
  float w01 = getWeight(uv, p01);
  float w11 = getWeight(uv, p11);

  // ── 3. Dynamic Color Shifting ────────────────────────────────────────────
  vec3 c00 = shiftPalette(t * 0.08, uColor0, uColor1, uShadow);
  vec3 c10 = shiftPalette(t * 0.07 + 1.0, uColor1, uColor2, uShadow);
  vec3 c01 = shiftPalette(t * 0.09 + 2.0, uColor2, uColor0, uHighlight);
  vec3 c11 = shiftPalette(t * 0.06 + 0.5, uShadow, uColor1, uColor2);

  float totalW = w00 + w10 + w01 + w11 + 0.001;
  vec3 col = (c00 * w00 + c10 * w10 + c01 * w01 + c11 * w11) / totalW;

  // ── 4. Subtle Ambient Shadow Blend ──────────────────────────────────────
  float shadowMask = smoothstep(0.2, 0.9, uv.y + 0.2 * sin(uv.x * 3.0 + t * 0.2));
  col = mix(col, uShadow, shadowMask * 0.12);

  // ── 5. Dithering Film Grain ─────────────────────────────────────────────
  vec2 grainUV = fragCoord + fract(t) * 82.2;
  float grain = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.02);

  // ── 6. Soft Vignette (Optimized) ────────────────────────────────────────
  vec2 vC = uv - 0.5;
  float vig = clamp(1.0 - dot(vC, vC) * 0.3, 0.0, 1.0); // No length() here baby
  col *= vig;

  fragColor = vec4(col, 1.0);
}
