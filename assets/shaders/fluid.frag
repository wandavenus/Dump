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
//
// Design principles:
//   • No loops, no heavy math chains.
//   • Two-axis domain warp (4 sin/cos calls) distorts the UV grid organically.
//   • Three scalar fields (5 sin/cos calls) each drive one colour transition.
//   • mix() blends the five palette colours without branching.
//   • Highlight/Shadow are blended at low weight using existing f0/f1/f2 as
//     natural bright/dark masks — zero additional trig calls.
//   • Total ~9 trig calls/pixel — fast on Adreno 618 at 256×512 render size.
// ─────────────────────────────────────────────────────────────────────────────

uniform vec2  uSize;
uniform float uTime;
uniform vec3  uColor0;     // primary   — dominant mood
uniform vec3  uColor1;     // secondary — supporting
uniform vec3  uColor2;     // accent    — vibrant pop
uniform vec3  uHighlight;  // highlight — bright ridges / glow peaks
uniform vec3  uShadow;     // shadow    — dark depth / valleys

out vec4 fragColor;

void main() {
  // Normalised UV in [0, 1].
  vec2 uv = FlutterFragCoord().xy / uSize;
  float t = uTime;

      // ── Domain warp (Softened for seamless blending) ─────────────────────────
  // Kita gedeein range blur-nya (sin * 0.25) biar warnanya keseret lebih jauh,
  // dan kecilin frekuensi-nya (y * 2.0) biar kerasa lebih adem.
  
  float wX1 = sin(uv.y * 2.0 + uv.x * 1.0 + t * 0.180) * 0.25; // Lebih lebar
  float wY1 = cos(uv.x * 2.2 + uv.y * 1.2 + t * 0.145) * 0.22; // Lebih lebar

  // Layer 2 kita bikin super subtle aja buat hancurin pola garis
  float wX2 = cos((uv.x + wX1) * 3.0 - t * 0.212) * 0.05; // Lebih halus
  float wY2 = sin((uv.y + wY1) * 2.8 + t * 0.145) * 0.04; // Lebih halus

  vec2 uvd = uv + vec2(wX1 + wX2, wY1 + wY2);


      // ── Scalar colour fields (Seamless Glow) ──────────────────────────────────
  // Rahasia biar ga kayak ORB:
  // 1. Kurangin pengali jarak (`dist1 * 1.5`), biar "lingkaran"-nya gede banget (nge-glow).
  // 2. Ganti `* 0.5 + 0.5` jadi range yang lebih sempit (misal `* 0.35 + 0.4`) 
  //    biar kontras antar warnanya ga terlalu ekstrim (ga ada bates tajem).

  // Pusat 1: Glow gede banget
  float dist1 = length(uvd - vec2(0.5 + sin(t * 0.10) * 0.3, 0.5 + cos(t * 0.15) * 0.3));
  float f0 = sin(dist1 * 1.7 - t * 0.15) * 0.35 + 0.4; 

  // Pusat 2: Interferensi tipis-tipis aja
  float f1 = sin(uvd.x * 1.8 + t * 0.08) * cos(uvd.y * 2.0 - t * 0.11) * 0.30 + 0.35;

  // Pusat 3: Glow kedua buat ngeramein blend
  float dist2 = length(uvd - vec2(0.3 + cos(t * 0.13) * 0.15, 0.7 + sin(t * 0.09) * 0.15));
  float f2 = cos(dist2 * 2.0 + t * 0.2) * 0.35 + 0.4;



  // ── Palette blend ──────────────────────────────────────────────────────────
  // Layer 1: Primary ↔ Secondary.
  //   Remap f0 from its natural [0.05, 0.75] range to full [0, 1] so each
  //   color owns clear, distinct territory instead of always mixing ~60/40.
  //   Before this fix the primary dominated ≈60% of every pixel.
  float b01 = clamp((f0 - 0.05) / 0.70, 0.0, 1.0);
  vec3 col = mix(uColor0, uColor1, b01);

  // Layer 2: Accent via f2 (circular glow field, range [0.05, 0.75]).
  //   Using f2 instead of f1 places accent in distinct circular patches
  //   rather than diffuse horizontal bands.  Max weight 0.85 lets accent
  //   fully dominate its glow centres, making artwork colors visually pop.
  float b2 = clamp((f2 - 0.05) / 0.70 * 0.85, 0.0, 0.85);
  col = mix(col, uColor2, b2);

  // Layer 3: Highlight — bright ridges where both glow fields peak.
  //   Weight raised 0.22 → 0.30 so highlight hue is more visible.
  float hBright = clamp((f0 + f2) * 0.5 - 0.37, 0.0, 1.0);
  col = mix(col, uHighlight, hBright * 0.30);

  // Layer 4: Shadow — dark valleys where the average field dips low.
  //   Weight raised 0.20 → 0.28 so depth color reads clearly.
  float hDark = clamp(0.47 - (f0 + f1 + f2) / 3.0, 0.0, 1.0);
  col = mix(col, uShadow, hDark * 0.28);

  // ── Soft vignette ──────────────────────────────────────────────────────────
  // Darkens the perimeter slightly so the centre feels like the light source.
  float vig = 1.0 - length(uv - 0.5) * 0.3;
  col *= clamp(vig, 0.0, 1.0);

  // ── Animated film grain ────────────────────────────────────────────
  // Hash function maps pixel position + time to a pseudo-random value in [0,1].
  // Multiplying uTime by a large prime shifts the hash pattern every frame so
  // the grain is always animated (no static texture repeating across frames).
  vec2 grainUV = FlutterFragCoord().xy + mod(uTime, 1.0) * 82.2;
  float grain   = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.02);

  fragColor = vec4(col, 1.0);
}
