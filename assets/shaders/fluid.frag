#include <flutter/runtime_effect.glsl>

// ─────────────────────────────────────────────────────────────────────────────
// fluid.frag  —  Ultra Light 3-Field Roaming Shader with Average Overlay
// ─────────────────────────────────────────────────────────────────────────────

uniform vec2  uSize;
uniform float uTime;
uniform vec3  uColor0;    // Dominant
uniform vec3  uColor1;    // Supporting
uniform vec3  uColor2;    // Accent
uniform vec3  uHighlight; // Bright pop (Ambient Overlay)
uniform vec3  uShadow;    // Dark depth (Ambient Overlay)

out vec4 fragColor;

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;
  float t = uTime;

  float aspect = uSize.x / uSize.y;
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);

  // ── 1. 3 Roaming Centers (3 Warna Utama Keliling Layar 0.15..0.85) ────────
  vec2 center0 = vec2(
      0.50 + 0.35 * sin(t * 0.083 + 0.5) + 0.05 * cos(t * 0.191),
      0.50 + 0.35 * cos(t * 0.061 + 1.2) + 0.05 * sin(t * 0.147));

  vec2 center1 = vec2(
      0.50 + 0.35 * sin(t * 0.071 + 2.4) + 0.06 * cos(t * 0.163),
      0.50 + 0.35 * cos(t * 0.093 + 0.8) + 0.04 * sin(t * 0.211));

  vec2 center2 = vec2(
      0.50 + 0.35 * sin(t * 0.053 + 4.1) + 0.05 * cos(t * 0.137),
      0.50 + 0.35 * cos(t * 0.079 + 3.1) + 0.05 * sin(t * 0.183));

  // ── 2. Distance & Field Calculation (Ukurannya Lebih Pass) ───────────────
  vec2 f0 = vec2((uv.x - center0.x) * aspect, uv.y - center0.y) / vec2(0.42 * aspect, 0.40);
  vec2 f1 = vec2((uv.x - center1.x) * aspect, uv.y - center1.y) / vec2(0.42 * aspect, 0.40);
  vec2 f2 = vec2((uv.x - center2.x) * aspect, uv.y - center2.y) / vec2(0.42 * aspect, 0.40);

  // Exponent 1.8 bikin bentuk gumpalan warna lebih terdefinisi tapi tetep smooth
  float l0 = exp(-dot(f0, f0) * 1.8);
  float l1 = exp(-dot(f1, f1) * 1.8);
  float l2 = exp(-dot(f2, f2) * 1.8);

  // Dynamic Pulsing (Detak warna)
  l0 *= 0.85 + 0.25 * sin(t * 0.17 + 0.2);
  l1 *= 0.85 + 0.25 * sin(t * 0.14 + 2.3);
  l2 *= 0.85 + 0.25 * sin(t * 0.11 + 4.0);

  // ── 3. Pure 3-Color Blending ──────────────────────────────────────────────
  // Kunci warna murni tanpa dicampur warna lain di tahap gumpalan
  float totalWeight = l0 + l1 + l2 + 0.001;
  vec3 col = (uColor0 * l0 + uColor1 * l1 + uColor2 * l2) / totalWeight;

  // ── 4. Ambient Highlight & Shadow Overlay (Average Lighting) ──────────────
  // Gradient pencahayaan lembut (Highlight di atas-kiri, Shadow di bawah-kanan)
  float lightGrad = dot(p, vec2(-0.5, -0.8)) + 0.5; // range ~0.0 sampai 1.0
  float hlPulse = 0.12 + 0.05 * sin(t * 0.10);
  float shPulse = 0.15 + 0.05 * cos(t * 0.08);

  // Blending rata (average) tanpa ngerusak warna dasar
  col = mix(col, uHighlight, smoothstep(0.3, 0.9, lightGrad) * hlPulse);
  col = mix(col, uShadow, smoothstep(0.7, 0.1, lightGrad) * shPulse);

  // ── 5. Fast Dithering Film Grain (Cegah Color Banding) ───────────────────
  vec2 grainUV = fragCoord + mod(t, 1.0) * 82.2;
  float grain = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.02);

  // ── 6. Soft Vignette ──────────────────────────────────────────────────────
  float vig = 1.0 - length(uv - 0.5) * 0.25;
  col *= clamp(vig, 0.0, 1.0);

  fragColor = vec4(col, 1.0);
}
