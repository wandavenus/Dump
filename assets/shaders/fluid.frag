#include <flutter/runtime_effect.glsl>

// ─────────────────────────────────────────────────────────────────────────────
// fluid.frag  —  Guaranteed multi-color chromatic dynamic field.
// ─────────────────────────────────────────────────────────────────────────────

uniform vec2  uSize;
uniform float uTime;
uniform vec3  uColor0;    // Dominant
uniform vec3  uColor1;    // Supporting
uniform vec3  uColor2;    // Accent
uniform vec3  uHighlight; // Bright pop
uniform vec3  uShadow;    // Dark depth

out vec4 fragColor;

// Fast 2D Pseudo-Noise
float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 uv = fragCoord / uSize;
  float t = uTime;

  // ── 1. Light Noise Displacement (Efek Cair Organik) ──────────────────────
  float nX = noise(uv * 2.2 + vec2(t * 0.04, 0.0));
  float nY = noise(uv * 2.2 + vec2(0.0, t * 0.04));
  vec2 distortedUV = uv + (vec2(nX, nY) - 0.5) * 0.025;

  float aspect = uSize.x / uSize.y;
  vec2 p = vec2((distortedUV.x - 0.5) * aspect, distortedUV.y - 0.5);

  // ── 2. Moving Centers (Tersebar Biar Ga Tumpuk Total) ──────────────────────
  // Tiap warna dapet orbit sendiri di sudut/area layar yang beda
  vec2 center0 = vec2(0.35 + 0.25 * sin(t * 0.11 + 0.5), 0.35 + 0.25 * cos(t * 0.08 + 1.2)); // Top-Left area
  vec2 center1 = vec2(0.65 + 0.25 * sin(t * 0.09 + 2.1), 0.35 + 0.25 * cos(t * 0.07 + 0.4)); // Top-Right area
  vec2 center2 = vec2(0.50 + 0.28 * sin(t * 0.13 + 4.2), 0.65 + 0.22 * cos(t * 0.09 + 2.8)); // Bottom Center
  vec2 center3 = vec2(0.25 + 0.20 * sin(t * 0.07 + 3.1), 0.70 + 0.20 * cos(t * 0.12 + 5.0)); // Bottom-Left area
  vec2 center4 = vec2(0.75 + 0.20 * sin(t * 0.10 + 1.8), 0.60 + 0.25 * cos(t * 0.06 + 3.5)); // Bottom-Right area

  // Distance calculations
  vec2 f0 = vec2((distortedUV.x - center0.x) * aspect, distortedUV.y - center0.y) / vec2(0.48 * aspect, 0.46);
  vec2 f1 = vec2((distortedUV.x - center1.x) * aspect, distortedUV.y - center1.y) / vec2(0.48 * aspect, 0.46);
  vec2 f2 = vec2((distortedUV.x - center2.x) * aspect, distortedUV.y - center2.y) / vec2(0.50 * aspect, 0.48);
  vec2 f3 = vec2((distortedUV.x - center3.x) * aspect, distortedUV.y - center3.y) / vec2(0.45 * aspect, 0.45);
  vec2 f4 = vec2((distortedUV.x - center4.x) * aspect, distortedUV.y - center4.y) / vec2(0.45 * aspect, 0.45);

  // Breathing size
  float l0 = exp(-dot(f0, f0) * 1.35);
  float l1 = exp(-dot(f1, f1) * 1.35);
  float l2 = exp(-dot(f2, f2) * 1.25);
  float l3 = exp(-dot(f3, f3) * 1.40);
  float l4 = exp(-dot(f4, f4) * 1.40);

  // Dynamic Intensity Pulsing
  l0 *= 0.85 + 0.25 * sin(t * 0.17 + 0.2);
  l1 *= 0.85 + 0.25 * sin(t * 0.14 + 2.3);
  l2 *= 0.85 + 0.25 * sin(t * 0.11 + 4.0);
  l3 *= 0.80 + 0.30 * sin(t * 0.18 + 1.0);
  l4 *= 0.80 + 0.30 * sin(t * 0.15 + 3.4);

  // ── 3. Color Assignment (Setiap Palet Terkunci + Blend Acak) ────────────
  // Anchor 70% warna asli, 30% dapet resapan warna lain yang berubah seiring waktu
  vec3 col0 = mix(uColor0, uColor1, 0.3 * (0.5 + 0.5 * sin(t * 0.12)));
  vec3 col1 = mix(uColor1, uColor2, 0.3 * (0.5 + 0.5 * cos(t * 0.09)));
  vec3 col2 = mix(uColor2, uColor0, 0.3 * (0.5 + 0.5 * sin(t * 0.15)));
  vec3 col3 = mix(uHighlight, uColor2, 0.35 * (0.5 + 0.5 * cos(t * 0.11))); // Always holds Highlight!
  vec3 col4 = mix(uShadow, uColor0, 0.35 * (0.5 + 0.5 * sin(t * 0.08)));    // Always holds Shadow!

  // Blend sum
  float totalWeight = l0 + l1 + l2 + l3 + l4 + 0.001;
  vec3 col = (col0 * l0 + col1 * l1 + col2 * l2 + col3 * l3 + col4 * l4) / totalWeight;

  // ── 4. Subtle Center Accents (Pertegas Highlight & Shadow) ───────────────
  float hlMask = exp(-dot((p - vec2(center3.x - 0.5, center3.y - 0.5)) * vec2(1.2, 1.2),
                          (p - vec2(center3.x - 0.5, center3.y - 0.5)) * vec2(1.2, 1.2)) * 3.5);
  col = mix(col, uHighlight, hlMask * 0.25);

  // ── 5. Dithering Film Grain ────────────────────────────────────────────────
  vec2 grainUV = fragCoord + mod(t, 1.0) * 82.2;
  float grain = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.02);

  // ── 6. Vignette ───────────────────────────────────────────────────────────
  float vig = 1.0 - length(uv - 0.5) * 0.25;
  col *= clamp(vig, 0.0, 1.0);

  fragColor = vec4(col, 1.0);
}
