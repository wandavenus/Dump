#include <flutter/runtime_effect.glsl>

// ─────────────────────────────────────────────────────────────────────────────
// fluid.frag  —  Dynamic Color-Shifting Mesh Gradient (No Static Color Nodes)
// ─────────────────────────────────────────────────────────────────────────────

uniform vec2  uSize;
uniform float uTime;
uniform vec3  uColor0;    // Dominant
uniform vec3  uColor1;    // Supporting
uniform vec3  uColor2;    // Accent
uniform vec3  uHighlight; // Bright pop
uniform vec3  uShadow;    // Dark depth

out vec4 fragColor;

// Helper function: Interpolasi mulus 3-way antar palet warna berbasis waktu
vec3 shiftPalette(float progress, vec3 colA, vec3 colB, vec3 colC) {
  float p = mod(progress, 3.0);
  if (p < 1.0) {
    return mix(colA, colB, smoothstep(0.0, 1.0, p));
  } else if (p < 2.0) {
    return mix(colB, colC, smoothstep(0.0, 1.0, p - 1.0));
  } else {
    return mix(colC, colA, smoothstep(0.0, 1.0, p - 2.0));
  }
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;
  float t = uTime;

  // ── 1. Mesh Grid Node Distortions (Sambil Meliuk Halus) ─────────────────
  vec2 p00 = vec2(0.0, 0.0) + vec2(0.20 * sin(t * 0.11), 0.20 * cos(t * 0.13)); // Top-Left Node
  vec2 p10 = vec2(1.0, 0.0) + vec2(0.20 * cos(t * 0.09), 0.20 * sin(t * 0.15)); // Top-Right Node
  vec2 p01 = vec2(0.0, 1.0) + vec2(0.20 * sin(t * 0.14), 0.20 * cos(t * 0.10)); // Bottom-Left Node
  vec2 p11 = vec2(1.0, 1.0) + vec2(0.20 * cos(t * 0.12), 0.20 * sin(t * 0.08)); // Bottom-Right Node

  // ── 2. Landai Smoothstep Weighting (Hapus Efek Bola Lampu) ───────────────
  float w00 = smoothstep(1.3, 0.0, length(uv - p00));
  float w10 = smoothstep(1.3, 0.0, length(uv - p10));
  float w01 = smoothstep(1.3, 0.0, length(uv - p01));
  float w11 = smoothstep(1.3, 0.0, length(uv - p11));

  // ── 3. Dynamic Color Shifting (Tiap Titik Warna Rotasi Terus) ─────────────
  // Pake shiftPalette() biar warna di tiap sudut muter lewat semua palet
  vec3 c00 = shiftPalette(t * 0.08 + 0.0, uColor0, uColor1, uHighlight);
  vec3 c10 = shiftPalette(t * 0.07 + 1.0, uColor1, uColor2, uShadow);
  vec3 c01 = shiftPalette(t * 0.09 + 2.0, uColor2, uColor0, uHighlight);
  vec3 c11 = shiftPalette(t * 0.06 + 0.5, uHighlight, uColor1, uColor2);

  // Blending Bilinear Rata Datar
  float totalW = w00 + w10 + w01 + w11 + 0.001;
  vec3 col = (c00 * w00 + c10 * w10 + c01 * w01 + c11 * w11) / totalW;

  // ── 4. Subtle Ambient Shadow Blend ──────────────────────────────────────
  float shadowMask = smoothstep(0.2, 0.9, uv.y + 0.2 * sin(uv.x * 3.0 + t * 0.2));
  col = mix(col, uShadow, shadowMask * 0.12);

  // ── 5. Dithering Film Grain (Cegah Color Banding) ───────────────────────
  vec2 grainUV = fragCoord + mod(t, 1.0) * 82.2;
  float grain = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.02);

  // ── 6. Soft Vignette ──────────────────────────────────────────────────────
  float vig = 1.0 - length(uv - 0.5) * 0.18;
  col *= clamp(vig, 0.0, 1.0);

  fragColor = vec4(col, 1.0);
}
