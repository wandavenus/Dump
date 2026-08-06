#include <flutter/runtime_effect.glsl>

// ─────────────────────────────────────────────────────────────────────────────
// fluid.frag  —  Pure Animated Color Field Background Shader
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

  // ── 1. Color Field Anchor Nodes (Titik Pusat Warna Field) ───────────────────
  // Dibuat 4 Field Node utama yang jalurnya saling bertabrakan & mengalir acak
  vec2 field0 = vec2(
      0.50 + 0.35 * sin(t * 0.11 + 0.3) + 0.10 * cos(t * 0.23),
      0.50 + 0.35 * cos(t * 0.09 + 1.1) + 0.08 * sin(t * 0.17));

  vec2 field1 = vec2(
      0.50 + 0.38 * cos(t * 0.08 + 2.5) - 0.12 * sin(t * 0.27),
      0.50 + 0.32 * sin(t * 0.14 + 0.7) + 0.10 * cos(t * 0.19));

  vec2 field2 = vec2(
      0.50 + 0.34 * sin(t * 0.13 + 4.1) - 0.09 * cos(t * 0.31),
      0.50 + 0.36 * cos(t * 0.07 + 2.8) - 0.11 * sin(t * 0.21));

  vec2 field3 = vec2(
      0.50 + 0.30 * cos(t * 0.10 + 1.8) + 0.14 * sin(t * 0.25),
      0.50 + 0.30 * sin(t * 0.15 + 3.2) - 0.09 * cos(t * 0.18));

  // ── 2. Color Field Weighting (Jarak Piksel ke Field Nodes) ────────────────
  // Menggunakan Squared Euclidean Distance buat interpolasi medan warna yang luas
  float d0 = length(vec2((uv.x - field0.x) * aspect, uv.y - field0.y));
  float d1 = length(vec2((uv.x - field1.x) * aspect, uv.y - field1.y));
  float d2 = length(vec2((uv.x - field2.x) * aspect, uv.y - field2.y));
  float d3 = length(vec2((uv.x - field3.x) * aspect, uv.y - field3.y));

  // Power curve buat bikin transisi batas medan warnanya sangat lembut (Field Effect)
  float w0 = 1.0 / (pow(d0, 1.8) + 0.001);
  float w1 = 1.0 / (pow(d1, 1.8) + 0.001);
  float w2 = 1.0 / (pow(d2, 1.8) + 0.001);
  float w3 = 1.0 / (pow(d3, 1.8) + 0.001);

  // Dynamic Pulsing Intensity per medan warna
  w0 *= 0.85 + 0.15 * sin(t * 0.22);
  w1 *= 0.85 + 0.15 * cos(t * 0.18);
  w2 *= 0.85 + 0.15 * sin(t * 0.25);
  w3 *= 0.85 + 0.15 * cos(t * 0.14);

  // ── 3. Color Field Blending ───────────────────────────────────────────────
  // Tiap node medan warna dapet porsi warna dari palet utama secara dinamis
  vec3 c0 = mix(uColor0, uColor1, 0.25 + 0.25 * sin(t * 0.15));
  vec3 c1 = mix(uColor1, uColor2, 0.25 + 0.25 * cos(t * 0.11));
  vec3 c2 = mix(uColor2, uColor0, 0.25 + 0.25 * sin(t * 0.19));
  vec3 c3 = mix(uColor0, uColor2, 0.25 + 0.25 * cos(t * 0.13));

  float totalW = w0 + w1 + w2 + w3;
  vec3 col = (c0 * w0 + c1 * w1 + c2 * w2 + c3 * w3) / totalW;

  // ── 4. Ambient Highlight & Shadow Lighting Overlay ─────────────────────────
  float lightGrad = dot(p, vec2(-0.4, -0.7)) + 0.5;
  float hlPulse = 0.10 + 0.04 * sin(t * 0.12);
  float shPulse = 0.14 + 0.04 * cos(t * 0.09);

  col = mix(col, uHighlight, smoothstep(0.2, 0.85, lightGrad) * hlPulse);
  col = mix(col, uShadow, smoothstep(0.8, 0.15, lightGrad) * shPulse);

  // ── 5. Dithering Film Grain ───────────────────────────────────────────────
  vec2 grainUV = fragCoord + mod(t, 1.0) * 82.2;
  float grain = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.02);

  // ── 6. Soft Vignette ──────────────────────────────────────────────────────
  float vig = 1.0 - length(uv - 0.5) * 0.22;
  col *= clamp(vig, 0.0, 1.0);

  fragColor = vec4(col, 1.0);
}
