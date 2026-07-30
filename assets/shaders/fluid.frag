#include <flutter/runtime_effect.glsl>

// ─────────────────────────────────────────────────────────────────────────────
// fluid.frag  —  Atmospheric colour-field shader for the player background.
//
// Uniforms (bound in order by Dart FragmentShader.setFloat):
//   0-1  : uSize      vec2   canvas size in logical pixels
//   2    : uTime      float  monotonically increasing time (seconds)
//   3-5  : uColor0    vec3   primary colour    (RGB 0-1)  — dominant mood
//   6-8  : uColor1    vec3   secondary colour  (RGB 0-1)  — supporting
//   9-11 : uColor2    vec3   accent colour     (RGB 0-1)  — vibrant pop
//   12-14: uHighlight vec3   highlight colour  (RGB 0-1)  — bright ridges
//   15-17: uShadow    vec3   shadow colour     (RGB 0-1)  — dark depth
// ─────────────────────────────────────────────────────────────────────────────

uniform vec2  uSize;
uniform float uTime;
uniform vec3  uColor0;
uniform vec3  uColor1;
uniform vec3  uColor2;
uniform vec3  uHighlight;
uniform vec3  uShadow;

out vec4 fragColor;

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;
  float t = uTime;

  // ── Fix Aspect Ratio ──
  float aspect = uSize.x / uSize.y;
  vec2 uvAdj = vec2(uv.x * aspect, uv.y);

  // ── Domain warp ──
  float wX1 = sin(uvAdj.y * 2.0 + uvAdj.x * 1.0 + t * 0.180) * 0.25;
  float wY1 = cos(uvAdj.x * 2.2 + uvAdj.y * 1.2 + t * 0.145) * 0.22;
  float wX2 = cos((uvAdj.x + wX1) * 3.0 - t * 0.212) * 0.05;
  float wY2 = sin((uvAdj.y + wY1) * 2.8 + t * 0.145) * 0.04;
  vec2 uvd = uvAdj + vec2(wX1 + wX2, wY1 + wY2);

  // ── Scalar colour fields ──
  float scale = 2.0;

  float dist1 = length(uvd - vec2(0.5 + sin(t * 0.10) * 0.3, 0.5 + cos(t * 0.15) * 0.3));
  float f0 = sin(dist1 * (1.7 * scale) - t * 0.15) * 0.35 + 0.4;

  float f1 = sin(uvd.x * (1.8 * scale) + t * 0.08) * cos(uvd.y * (2.0 * scale) - t * 0.11) * 0.30 + 0.35;

  float dist2 = length(uvd - vec2(0.3 + cos(t * 0.13) * 0.15, 0.7 + sin(t * 0.09) * 0.15));
  float f2 = cos(dist2 * (2.0 * scale) + t * 0.2) * 0.35 + 0.4;

  float dist3 = length(uvd - vec2(0.8 - sin(t * 0.12) * 0.25, 0.2 + cos(t * 0.14) * 0.20));
  float f3 = sin(dist3 * (2.2 * scale) - t * 0.18) * 0.30 + 0.35;

  float f4 = cos(uvd.x * (2.5 * scale) - t * 0.16) * sin(uvd.y * (1.8 * scale) + t * 0.12) * 0.25 + 0.30;

  // ── Palette blend (tanpa mixVibrant) ──
  // Weighted average dari semua field
  float total = f0 + f1 + f2 + f3 + f4;
  float w0 = f0 / total;
  float w1 = f1 / total;
  float w2 = f2 / total;
  float w3 = f3 / total;
  float w4 = f4 / total;

  // Campur warna dasar (Primary, Secondary, Accent)
  vec3 col = uColor0 * w0 + uColor1 * w1 + uColor2 * w2;

  // Highlight & shadow sebagai sentuhan halus (15% efek)
  float avgField = (f0 + f1 + f2 + f3 + f4) / 5.0;

  float hBright = smoothstep(0.5, 0.8, avgField);
  col = mix(col, uHighlight, hBright * 0.35);

  float hDark = smoothstep(0.3, 0.05, avgField);
  col = mix(col, uShadow, hDark * 0.05);

  // ── Soft vignette ──
  float vig = 1.0 - length(uv - 0.5) * 0.3;
  col *= clamp(vig, 0.0, 1.0);

  // ── Film grain ──
  vec2 grainUV = fragCoord + mod(t, 1.0) * 82.2;
  float grain = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.02);

  fragColor = vec4(col, 1.0);
}
