#include <flutter/runtime_effect.glsl>

// ─────────────────────────────────────────────────────────────────────────────
// fluid.frag  —  Atmospheric colour-field shader for the player background.
//
// Uniforms (bound in order by Dart FragmentShader.setFloat):
//   0-1  : uSize      vec2   canvas size in logical pixels
//   2    : uTime      float  monotonically increasing time (seconds)
//   3-5  : uColor0    vec3   dominant colour  (RGB 0-1)
//   6-8  : uColor1    vec3   vibrant colour   (RGB 0-1)
//   9-11 : uColor2    vec3   muted colour     (RGB 0-1)
//
// Design principles:
//   • No loops, no heavy math chains.
//   • Two-axis domain warp (4 sin/cos calls) distorts the UV grid organically.
//   • Three scalar fields (5 sin/cos calls) each drive one colour transition.
//   • mix() blends the three palette colours without branching.
//   • Total ~9 trig calls/pixel — fast on Adreno 618 at 256×512 render size.
// ─────────────────────────────────────────────────────────────────────────────

uniform vec2  uSize;
uniform float uTime;
uniform vec3  uColor0;   // dominant
uniform vec3  uColor1;   // vibrant
uniform vec3  uColor2;   // muted

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
  float f0 = sin(dist1 * 1.5 - t * 0.15) * 0.35 + 0.4; // Halus range-nya

  // Pusat 2: Interferensi tipis-tipis aja
  float f1 = sin(uvd.x * 1.8 + t * 0.08) * cos(uvd.y * 2.0 - t * 0.11) * 0.30 + 0.35;

  // Pusat 3: Glow kedua buat ngeramein blend
  float dist2 = length(uvd - vec2(0.3 + cos(t * 0.13) * 0.15, 0.7 + sin(t * 0.09) * 0.15));
  float f2 = cos(dist2 * 1.8 + t * 0.2) * 0.35 + 0.4;



  // ── Palette blend ──────────────────────────────────────────────────────────
  // Layered mix() calls fold all three colours together.  The weights (0.55,
  // 0.25) keep the dominant colour prominent while the other two add richness.
  vec3 col = mix(uColor0, uColor1, f0);
  col      = mix(col,     uColor2, f1 * 0.55);
  col      = mix(col,     uColor0, f2 * 0.25);

  // ── Soft vignette ──────────────────────────────────────────────────────────
  // Darkens the perimeter slightly so the centre feels like the light source.
  float vig = 1.0 - length(uv - 0.5) * 0.50;
  col *= clamp(vig, 0.0, 1.0);

  // ── Animated film grain (0.5 %) ────────────────────────────────────────────
  // Hash function maps pixel position + time to a pseudo-random value in [0,1].
  // Multiplying uTime by a large prime shifts the hash pattern every frame so
  // the grain is always animated (no static texture repeating across frames).
  vec2 grainUV = FlutterFragCoord().xy + mod(uTime, 1.0) * 82.2;
  float grain   = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.02);

  fragColor = vec4(col, 1.0);
}
