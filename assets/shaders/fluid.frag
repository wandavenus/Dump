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

    // ── Domain warp (Apple Music Style Randomizer) ─────────────────────────────
  // Kita campur x dan y di setiap wave, dan tambahin noise frekuensi tinggi
  // biar arah pergerakannya ga ketebak (ga linear).
  
  // Layer 1: Pergerakan macro (gerakan lambat buat geser massa warna)
  float wX1 = sin(uv.y * 2.5 + uv.x * 1.2 + t * 0.210) * 0.18;
  float wY1 = cos(uv.x * 2.8 + uv.y * 1.5 + t * 0.165) * 0.15;

  // Layer 2: Pergerakan micro (bikin pusaran/arah putar yang random)
  float wX2 = cos((uv.x + wX1) * 4.2 - t * 0.312) * 0.08;
  float wY2 = sin((uv.y + wY1) * 3.8 + t * 0.245) * 0.07;

  // Gabungin semua buat dapet warped UV yang chaotic tapi tetep smooth
  vec2 uvd = uv + vec2(wX1 + wX2, wY1 + wY2);


  // ── Scalar colour fields ───────────────────────────────────────────────────
  // Each field produces a smooth value in [0, 1].  Using both x and y of the
  // warped UV plus an independent time rate ensures the three fields evolve
  // at different speeds and never lock into the same phase.
  float f0 = sin(uvd.x * 2.10 + uvd.y * 1.84 + t * 0.222) * 0.5 + 0.5;
  float f1 = cos(uvd.x * 1.73 - uvd.y * 2.30 - t * 0.156) * 0.5 + 0.5;
  float f2 = sin(uvd.x * 1.50 + uvd.y * 1.20 + t * 0.264) * 0.5 + 0.5;

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
  vec2  grainUV = FlutterFragCoord().xy + uTime * 82.2;
  float grain   = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.01);

  fragColor = vec4(col, 1.0);
}
