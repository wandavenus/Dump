#include <flutter/runtime_effect.glsl>

// ─────────────────────────────────────────────────────────────────────────────
// fluid.frag  —  Flat Animated Mesh Gradient (No Sphere / No Hotspots)
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

  // ── 1. Mesh Grid Node Distortions (Distorsi Jaring Grid) ────────────────
  // Bayangin canvas dibagi 4 sudut mesh (Top-Left, Top-Right, Bottom-Left, Bottom-Right)
  // Tiap titik jaring kita geser-geser dikit posisinya biar jaringnya meliuk lentur.
  
  vec2 p00 = vec2(0.0, 0.0) + vec2(0.20 * sin(t * 0.11), 0.20 * cos(t * 0.13)); // Top-Left Node
  vec2 p10 = vec2(1.0, 0.0) + vec2(0.20 * cos(t * 0.09), 0.20 * sin(t * 0.15)); // Top-Right Node
  vec2 p01 = vec2(0.0, 1.0) + vec2(0.20 * sin(t * 0.14), 0.20 * cos(t * 0.10)); // Bottom-Left Node
  vec2 p11 = vec2(1.0, 1.0) + vec2(0.20 * cos(t * 0.12), 0.20 * sin(t * 0.08)); // Bottom-Right Node

  // ── 2. Landai Smoothstep Weighting (Hapus Efek 'Pusat Bola Lampu') ───────
  // Pake Smoothstep biar transisi jaraknya rata datar & gak ada titik silau di tengah
  float w00 = smoothstep(1.3, 0.0, length(uv - p00));
  float w10 = smoothstep(1.3, 0.0, length(uv - p10));
  float w01 = smoothstep(1.3, 0.0, length(uv - p01));
  float w11 = smoothstep(1.3, 0.0, length(uv - p11));

  // ── 3. Dynamic Color Assignment per Node Mesh ─────────────────────────────
  // Warna di tiap sudut jaring saling tukeran warna dengan mulus
  vec3 c00 = mix(uColor0, uColor1, 0.3 * (0.5 + 0.5 * sin(t * 0.14)));
  vec3 c10 = mix(uColor1, uColor2, 0.3 * (0.5 + 0.5 * cos(t * 0.11)));
  vec3 c01 = mix(uColor2, uColor0, 0.3 * (0.5 + 0.5 * sin(t * 0.17)));
  vec3 c11 = mix(uHighlight, uColor1, 0.3 * (0.5 + 0.5 * cos(t * 0.09)));

  // Blending Bilinear rata
  float totalW = w00 + w10 + w01 + w11 + 0.001;
  vec3 col = (c00 * w00 + c10 * w10 + c01 * w01 + c11 * w11) / totalW;

  // ── 4. Ambient Shadow Blend (Biar Tetep Berdimensi Datar) ─────────────────
  float shadowMask = smoothstep(0.2, 0.9, uv.y + 0.2 * sin(uv.x * 3.0 + t * 0.2));
  col = mix(col, uShadow, shadowMask * 0.15);

  // ── 5. Dithering Film Grain ───────────────────────────────────────────────
  vec2 grainUV = fragCoord + mod(t, 1.0) * 82.2;
  float grain = fract(sin(dot(grainUV, vec2(127.1, 311.7))) * 43758.5453);
  col = mix(col, vec3(grain), 0.02);

  // ── 6. Soft Vignette ──────────────────────────────────────────────────────
  float vig = 1.0 - length(uv - 0.5) * 0.18;
  col *= clamp(vig, 0.0, 1.0);

  fragColor = vec4(col, 1.0);
}
