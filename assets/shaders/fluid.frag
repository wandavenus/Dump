#include <flutter/runtime_effect.glsl>

// ─────────────────────────────────────────────────────────────────────────────
// fluid.frag  —  Ultra Light Full-Screen Roaming Shader (No Noise)
// ─────────────────────────────────────────────────────────────────────────────

uniform vec2  uSize;
uniform float uTime;
uniform vec3  uColor0;    // Dominant
uniform vec3  uColor1;    // Supporting
uniform vec3  uColor2;    // Accent
uniform vec3  uHighlight; // Bright pop
uniform vec3  uShadow;    // Dark depth

out vec4 fragColor;

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;
  float t = uTime;

  float aspect = uSize.x / uSize.y;
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);

  // ── 1. Fully Roaming Centers (Keliling Layar Tanpa Noise) ─────────────────
  // Tiap pusat layer tetep jalan-jalan ke seluruh sudut 0.12..0.88
  vec2 center0 = vec2(
      0.50 + 0.38 * sin(t * 0.083 + 0.5) + 0.05 * cos(t * 0.191),
      0.50 + 0.38 * cos(t * 0.061 + 1.2) + 0.05 * sin(t * 0.147));

  vec2 center1 = vec2(
      0.50 + 0.37 * sin(t * 0.071 + 2.4) + 0.06 * cos(t * 0.163),
      0.50 + 0.37 * cos(t * 0.093 + 0.8) + 0.04 * sin(t * 0.211));

  vec2 center2 = vec2(
      0.50 + 0.38 * sin(t * 0.053 + 4.1) + 0.05 * cos(t * 0.137),
      0.50 + 0.38 * cos(t * 0.079 + 3.1) + 0.05 * sin(t * 0.183));

  vec2 center3 = vec2(
      0.50 + 0.36 * sin(t * 0.089 + 1.7) + 0.06 * cos(t * 0.113),
      0.50 + 0.36 * cos(t * 0.057 + 4.5) + 0.05 * sin(t * 0.159));

  vec2 center4 = vec2(
      0.50 + 0.37 * sin(t * 0.067 + 3.2) + 0.05 * cos(t * 0.179),
      0.50 + 0.37 * cos(t * 0.081 + 2.1) + 0.06 * sin(t * 0.127));

  // ── 2. Distance & Gaussian Field Calculation ─────────────────────────────
  vec2 f0 = vec2((uv.x - center0.x) * aspect, uv.y - center0.y) / vec2(0.50 * aspect, 0.48);
  vec2 f1 = vec2((uv.x - center1.x) * aspect, uv.y - center1.y) / vec2(0.50 * aspect, 0.48);
  vec2 f2 = vec2((uv.x - center2.x) * aspect, uv.y - center2.y) / vec2(0.52 * aspect, 0.50);
  vec2 f3 = vec2((uv.x - center3.x) * aspect, uv.y - center3.y) / vec2(0.48 * aspect, 0.46);
  vec2 f4 = vec2((uv.x - center4.x) * aspect, uv.y - center4.y) / vec2(0.48 * aspect, 0.46);

  // Breathing size & field intensity
  float l0 = exp(-dot(f0, f0) * 1.30);
  float l1 = exp(-dot(f1, f1) * 1.30);
  float l2 = exp(-dot(f2, f2) * 1.20);
  float l3 = exp(-dot(f3, f3) * 1.35);
  float l4 = exp(-dot(f4, f4) * 1.35);

  // Dynamic Intensity Pulsing
  l0 *= 0.85 + 0.25 * sin(t * 0.17 + 0.2);
  l1 *= 0.85 + 0.25 * sin(t * 0.14 + 2.3);
  l2 *= 0.85 + 0.25 * sin(t * 0.11 + 4.0);
  l3 *= 0.80 + 0.30 * sin(t * 0.18 + 1.0);
  l4 *= 0.80 + 0.30 * sin(t * 0.15 + 3.4);

  // ── 3. Locked Palette Anchors (Semua Warna Terkunci & Blend Soft) ─────────
  vec3 col0 = mix(uColor0, uColor1, 0.3 * (0.5 + 0.5 * sin(t * 0.12)));
  vec3 col1 = mix(uColor1, uColor2, 0.3 * (0.5 + 0.5 * cos(t * 0.09)));
  vec3 col2 = mix(uColor2, uColor0, 0.3 * (0.5 + 0.5 * sin(t * 0.15)));
  vec3 col3 = mix(uHighlight, uColor2, 0.35 * (0.5 + 0.5 * cos(t * 0.11))); // Pegang Highlight
  vec3 col4 = mix(uShadow, uColor0, 0.35 * (0.5 + 0.5 * sin(t * 0.08)));    // Pegang Shadow

  // Blend sum
  float totalWeight = l0 + l1 + l2 + l3 + l4 + 0.001;
  vec3 col = (col0 * l0 + col1 * l1 + col2 * l2 + col3 * l3 + col4 * l4) / totalWeight;

  // ── 4. Subtle Center Accents ──────────────────────────────────────────────
  float hlMask = exp(-dot((p - vec2(center3.x - 0.5, center3.y - 0.5)) * vec2(1.2, 1.2),
                          (p - vec2(center3.x - 0.5, center3.y - 0.5)) * vec2(1.2, 1.2)) * 3.5);
  col = mix(col, uHighlight, hlMask * 0.20);

  // ── 5. Fast Screen-Space Dithering (Cegah Color Banding) ─────────────────
  vec2 grainUV = fragCoord + mod(t, 1.0) * 82.2;
  float grain = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.02);

  // ── 6. Soft Vignette ──────────────────────────────────────────────────────
  float vig = 1.0 - length(uv - 0.5) * 0.25;
  col *= clamp(vig, 0.0, 1.0);

  fragColor = vec4(col, 1.0);
}
