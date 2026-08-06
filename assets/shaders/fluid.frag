#include <flutter/runtime_effect.glsl>

// ─────────────────────────────────────────────────────────────────────────────
// fluid.frag  —  Free-Flowing Organic Fluid Blend Shader (Non-Circular Motion)
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

  // ── 1. Free-Flowing Chaotic Movement (Gerak Bebas Acak & Saling Silang) ────
  // Pake kombinasi gelombang multiphase biar gak kerasa 'muter-muter' melingkar
  vec2 center0 = vec2(
      0.50 + 0.28 * sin(t * 0.13) + 0.12 * cos(t * 0.29 + 1.4),
      0.50 + 0.30 * cos(t * 0.11 + 0.8) + 0.10 * sin(t * 0.23)
  );

  vec2 center1 = vec2(
      0.50 + 0.32 * cos(t * 0.09 + 2.1) - 0.10 * sin(t * 0.31),
      0.50 + 0.26 * sin(t * 0.17 + 3.5) + 0.12 * cos(t * 0.19 + 0.2)
  );

  vec2 center2 = vec2(
      0.50 + 0.30 * sin(t * 0.15 + 4.2) - 0.12 * cos(t * 0.27 + 1.1),
      0.50 + 0.28 * cos(t * 0.07 + 1.7) - 0.11 * sin(t * 0.21 + 2.8)
  );

  // ── 2. Distance & Field Calculation ──────────────────────────────────────
  vec2 f0 = vec2((uv.x - center0.x) * aspect, uv.y - center0.y) / vec2(0.45 * aspect, 0.43);
  vec2 f1 = vec2((uv.x - center1.x) * aspect, uv.y - center1.y) / vec2(0.45 * aspect, 0.43);
  vec2 f2 = vec2((uv.x - center2.x) * aspect, uv.y - center2.y) / vec2(0.45 * aspect, 0.43);

  // Exponent Gaussian buat gumpalan warna
  float l0 = exp(-dot(f0, f0) * 1.6);
  float l1 = exp(-dot(f1, f1) * 1.6);
  float l2 = exp(-dot(f2, f2) * 1.6);

  // Intensity Breathing (Terang-redup gumpalan biar makin cair)
  l0 *= 0.82 + 0.28 * sin(t * 0.21 + 0.5);
  l1 *= 0.82 + 0.28 * cos(t * 0.18 + 2.2);
  l2 *= 0.82 + 0.28 * sin(t * 0.25 + 4.1);

  // ── 3. Organic Fluid Color Blending (Saling Nyampur & Peleburan) ───────────
  // Tiap warna dapet "resapan" warna temannya tergantung kedekatan & waktu
  vec3 col0 = mix(uColor0, uColor1, 0.20 + 0.20 * sin(t * 0.14));
  vec3 col1 = mix(uColor1, uColor2, 0.20 + 0.20 * cos(t * 0.12));
  vec3 col2 = mix(uColor2, uColor0, 0.20 + 0.20 * sin(t * 0.16));

  float totalWeight = l0 + l1 + l2 + 0.001;
  vec3 col = (col0 * l0 + col1 * l1 + col2 * l2) / totalWeight;

  // ── 4. Ambient Highlight & Shadow Overlay ─────────────────────────────────
  float lightGrad = dot(p, vec2(-0.5, -0.8)) + 0.5;
  float hlPulse = 0.12 + 0.05 * sin(t * 0.10);
  float shPulse = 0.15 + 0.05 * cos(t * 0.08);

  col = mix(col, uHighlight, smoothstep(0.3, 0.9, lightGrad) * hlPulse);
  col = mix(col, uShadow, smoothstep(0.7, 0.1, lightGrad) * shPulse);

  // ── 5. Fast Dithering Film Grain ──────────────────────────────────────────
  vec2 grainUV = fragCoord + mod(t, 1.0) * 82.2;
  float grain = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.02);

  // ── 6. Soft Vignette ──────────────────────────────────────────────────────
  float vig = 1.0 - length(uv - 0.5) * 0.25;
  col *= clamp(vig, 0.0, 1.0);

  fragColor = vec4(col, 1.0);
}
